export type HistoryRange = '24h' | '7d' | '30d' | 'all';

export interface RawListing {
  pk: string;
  sk: string;
  timestamp: string;
  amount: number;
  listingPrice: number;
  item: {
    name: string;
    itemType: string;
    type?: string;
    rarity?: string;
    tier?: number;
  };
}

export interface MarketObservation {
  timestamp: string;
  price: number;
  amount: number;
}

export interface CatalogItem {
  id: string;
  name: string;
  itemType: string;
  itemTypeLabel: string;
  type?: string;
  rarity?: string;
  tier?: number;
  observationCount: number;
  latestPrice: number;
  lastSeen: string;
}

export interface HistoryPoint {
  timestamp: string;
  medianPrice: number;
  lowestPrice: number;
  highestPrice: number;
  observationCount: number;
}

export interface ItemHistory {
  item: CatalogItem;
  range: HistoryRange;
  summary: {
    latestPrice: number;
    lowestPrice: number;
    medianPrice: number;
    observedVolume: number;
    observationCount: number;
    changeFromMedianPercent: number;
    firstSeen: string;
    lastSeen: string;
  };
  series: HistoryPoint[];
  recent: MarketObservation[];
}

interface MutableItem {
  id: string;
  itemType: string;
  type?: string;
  rarity?: string;
  tier?: number;
  names: Map<string, number>;
  observations: MarketObservation[];
}

const RANGE_MILLISECONDS: Record<Exclude<HistoryRange, 'all'>, number> = {
  '24h': 24 * 60 * 60 * 1000,
  '7d': 7 * 24 * 60 * 60 * 1000,
  '30d': 30 * 24 * 60 * 60 * 1000,
};

export function normalizeName(name: string): string {
  return name.normalize('NFKC').trim().replace(/\s+/g, ' ').toLocaleLowerCase('en-US');
}

export function createItemId(itemType: string, name: string, tier?: number): string {
  return `${itemType}::${normalizeName(name)}::${tier ?? ''}`;
}

export function formatItemType(itemType: string): string {
  return itemType
    .replace(/Item$/, '')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .trim();
}

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? Math.round((sorted[middle - 1] + sorted[middle]) / 2)
    : sorted[middle];
}

function preferredName(names: Map<string, number>): string {
  return [...names.entries()]
    .sort(([leftName, leftCount], [rightName, rightCount]) =>
      rightCount - leftCount || leftName.localeCompare(rightName),
    )[0]?.[0] ?? 'Unknown item';
}

function bucketDuration(range: HistoryRange, observations: MarketObservation[]): number {
  if (range === '24h') return 60 * 60 * 1000;
  if (range === '7d') return 6 * 60 * 60 * 1000;
  if (range === '30d') return 24 * 60 * 60 * 1000;

  const first = Date.parse(observations[0]?.timestamp ?? '');
  const last = Date.parse(observations.at(-1)?.timestamp ?? '');
  const span = Number.isFinite(first) && Number.isFinite(last) ? Math.max(last - first, 1) : 1;
  return Math.max(60 * 60 * 1000, Math.ceil(span / 72));
}

function bucketObservations(observations: MarketObservation[], range: HistoryRange): HistoryPoint[] {
  if (observations.length === 0) return [];
  const duration = bucketDuration(range, observations);
  const buckets = new Map<number, MarketObservation[]>();

  for (const observation of observations) {
    const timestamp = Date.parse(observation.timestamp);
    if (!Number.isFinite(timestamp)) continue;
    const bucket = Math.floor(timestamp / duration) * duration;
    const values = buckets.get(bucket) ?? [];
    values.push(observation);
    buckets.set(bucket, values);
  }

  return [...buckets.entries()]
    .sort(([left], [right]) => left - right)
    .map(([timestamp, values]) => {
      const prices = values.map((value) => value.price);
      return {
        timestamp: new Date(timestamp).toISOString(),
        medianPrice: median(prices),
        lowestPrice: Math.min(...prices),
        highestPrice: Math.max(...prices),
        observationCount: values.length,
      };
    });
}

export class MarketIndex {
  private readonly items = new Map<string, MutableItem>();
  private readonly seenListings = new Set<string>();
  private readonly latestKeys = new Map<string, string>();

  addListings(listings: RawListing[]): number {
    let added = 0;
    for (const listing of listings) {
      if (!this.addListing(listing)) continue;
      added += 1;
    }
    return added;
  }

  addListing(listing: RawListing): boolean {
    if (!listing.pk || !listing.sk || !listing.item.name || listing.listingPrice < 0) return false;

    const listingId = `${listing.pk}::${listing.sk}`;
    if (this.seenListings.has(listingId)) return false;
    this.seenListings.add(listingId);

    const itemType = listing.item.itemType || listing.pk;
    const id = createItemId(itemType, listing.item.name, listing.item.tier);
    let item = this.items.get(id);
    if (!item) {
      item = {
        id,
        itemType,
        type: listing.item.type,
        rarity: listing.item.rarity,
        tier: listing.item.tier,
        names: new Map(),
        observations: [],
      };
      this.items.set(id, item);
    }

    item.names.set(listing.item.name, (item.names.get(listing.item.name) ?? 0) + 1);
    item.observations.push({
      timestamp: listing.timestamp,
      price: listing.listingPrice,
      amount: listing.amount,
    });

    const latestKey = this.latestKeys.get(listing.pk);
    if (!latestKey || listing.sk > latestKey) this.latestKeys.set(listing.pk, listing.sk);
    return true;
  }

  getCatalog(): CatalogItem[] {
    return [...this.items.values()]
      .map((item) => this.toCatalogItem(item))
      .sort((left, right) =>
        left.itemTypeLabel.localeCompare(right.itemTypeLabel)
        || left.name.localeCompare(right.name)
        || (left.tier ?? 0) - (right.tier ?? 0),
      );
  }

  getHistory(id: string, range: HistoryRange, now = Date.now()): ItemHistory | null {
    const item = this.items.get(id);
    if (!item) return null;

    const cutoff = range === 'all' ? Number.NEGATIVE_INFINITY : now - RANGE_MILLISECONDS[range];
    const observations = item.observations
      .filter((observation) => Date.parse(observation.timestamp) >= cutoff)
      .sort((left, right) => Date.parse(left.timestamp) - Date.parse(right.timestamp));

    if (observations.length === 0) {
      return {
        item: this.toCatalogItem(item),
        range,
        summary: {
          latestPrice: 0,
          lowestPrice: 0,
          medianPrice: 0,
          observedVolume: 0,
          observationCount: 0,
          changeFromMedianPercent: 0,
          firstSeen: '',
          lastSeen: '',
        },
        series: [],
        recent: [],
      };
    }

    const prices = observations.map((observation) => observation.price);
    const medianPrice = median(prices);
    const latest = observations.at(-1)!;

    return {
      item: this.toCatalogItem(item),
      range,
      summary: {
        latestPrice: latest.price,
        lowestPrice: Math.min(...prices),
        medianPrice,
        observedVolume: observations.reduce((total, observation) => total + observation.amount, 0),
        observationCount: observations.length,
        changeFromMedianPercent: medianPrice === 0 ? 0 : ((latest.price - medianPrice) / medianPrice) * 100,
        firstSeen: observations[0].timestamp,
        lastSeen: latest.timestamp,
      },
      series: bucketObservations(observations, range),
      recent: observations.slice(-12).reverse(),
    };
  }

  getItemTypes(): string[] {
    return [...new Set([...this.items.values()].map((item) => item.itemType))].sort();
  }

  getLatestKey(itemType: string): string | undefined {
    return this.latestKeys.get(itemType);
  }

  get recordCount(): number {
    return this.seenListings.size;
  }

  get itemCount(): number {
    return this.items.size;
  }

  private toCatalogItem(item: MutableItem): CatalogItem {
    const observations = [...item.observations]
      .sort((left, right) => Date.parse(left.timestamp) - Date.parse(right.timestamp));
    const latest = observations.at(-1)!;
    return {
      id: item.id,
      name: preferredName(item.names),
      itemType: item.itemType,
      itemTypeLabel: formatItemType(item.itemType),
      type: item.type,
      rarity: item.rarity,
      tier: item.tier,
      observationCount: observations.length,
      latestPrice: latest.price,
      lastSeen: latest.timestamp,
    };
  }
}
