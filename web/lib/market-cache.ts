import {
  DynamoDBClient,
  QueryCommand,
  ScanCommand,
  type AttributeValue,
} from '@aws-sdk/client-dynamodb';
import { createDemoListings } from './demo-data';
import { MarketIndex, type HistoryRange, type RawListing } from './market';

interface ListingSource {
  scanAll(onPage: (listings: RawListing[]) => void): Promise<void>;
  queryAfter(itemType: string, sortKey: string): Promise<RawListing[]>;
}

const PROJECTION_EXPRESSION = 'pk, sk, #timestamp, amount, listingPrice, #item';
const EXPRESSION_ATTRIBUTE_NAMES = { '#timestamp': 'timestamp', '#item': 'item' };
const KNOWN_ITEM_TYPES = [
  'SimulatorItem',
  'InsulatorItem',
  'RuneItem',
  'DungeonKeyItem',
  'EmeraldItem',
  'AspectItem',
  'TomeItem',
  'IngredientItem',
  'MaterialItem',
  'PowderItem',
  'AmplifierItem',
  'MountItem',
  'EmeraldPouchItem',
];

function stringValue(value: AttributeValue | undefined): string | undefined {
  return value && 'S' in value ? value.S : undefined;
}

function numberValue(value: AttributeValue | undefined): number | undefined {
  if (!value || !('N' in value) || value.N === undefined) return undefined;
  const parsed = Number(value.N);
  return Number.isFinite(parsed) ? parsed : undefined;
}

export function parseDynamoListing(record: Record<string, AttributeValue>): RawListing | null {
  const pk = stringValue(record.pk);
  const sk = stringValue(record.sk);
  const item = record.item && 'M' in record.item ? record.item.M : undefined;
  const name = stringValue(item?.name);
  const listingPrice = numberValue(record.listingPrice);

  if (!pk || !sk || !item || !name || listingPrice === undefined) return null;

  return {
    pk,
    sk,
    timestamp: stringValue(record.timestamp) ?? sk.split('_')[0],
    amount: numberValue(record.amount) ?? 1,
    listingPrice,
    item: {
      name,
      itemType: stringValue(item.itemType) ?? pk,
      type: stringValue(item.type),
      rarity: stringValue(item.rarity),
      tier: numberValue(item.tier),
    },
  };
}

class DynamoListingSource implements ListingSource {
  private readonly client: DynamoDBClient;
  private readonly tableName: string;

  constructor() {
    this.client = new DynamoDBClient({
      region: process.env.AWS_REGION ?? process.env.WYNNMARKET_AWS_REGION ?? 'us-east-1',
    });
    this.tableName = process.env.WYNNMARKET_DYNAMODB_TABLE ?? 'wynnmarket-trade-market-listings';
  }

  async scanAll(onPage: (listings: RawListing[]) => void): Promise<void> {
    let exclusiveStartKey: Record<string, AttributeValue> | undefined;
    do {
      const response = await this.client.send(new ScanCommand({
        TableName: this.tableName,
        ExclusiveStartKey: exclusiveStartKey,
        ProjectionExpression: PROJECTION_EXPRESSION,
        ExpressionAttributeNames: EXPRESSION_ATTRIBUTE_NAMES,
        ConsistentRead: false,
      }));
      onPage((response.Items ?? []).flatMap((record) => {
        const listing = parseDynamoListing(record);
        return listing ? [listing] : [];
      }));
      exclusiveStartKey = response.LastEvaluatedKey;
    } while (exclusiveStartKey);
  }

  async queryAfter(itemType: string, sortKey: string): Promise<RawListing[]> {
    const listings: RawListing[] = [];
    let exclusiveStartKey: Record<string, AttributeValue> | undefined;
    do {
      const response = await this.client.send(new QueryCommand({
        TableName: this.tableName,
        ExclusiveStartKey: exclusiveStartKey,
        KeyConditionExpression: 'pk = :itemType AND sk > :sortKey',
        ExpressionAttributeValues: {
          ':itemType': { S: itemType },
          ':sortKey': { S: sortKey },
        },
        ProjectionExpression: PROJECTION_EXPRESSION,
        ExpressionAttributeNames: EXPRESSION_ATTRIBUTE_NAMES,
        ConsistentRead: false,
      }));
      for (const record of response.Items ?? []) {
        const listing = parseDynamoListing(record);
        if (listing) listings.push(listing);
      }
      exclusiveStartKey = response.LastEvaluatedKey;
    } while (exclusiveStartKey);
    return listings;
  }
}

class DemoListingSource implements ListingSource {
  async scanAll(onPage: (listings: RawListing[]) => void): Promise<void> {
    onPage(createDemoListings());
  }

  async queryAfter(): Promise<RawListing[]> {
    return [];
  }
}

export interface CacheStatus {
  state: 'idle' | 'loading' | 'ready' | 'error';
  recordCount: number;
  itemCount: number;
  lastRefreshAt: string | null;
  error?: string;
  source: 'dynamodb' | 'demo';
}

export class MarketCache {
  private readonly index = new MarketIndex();
  private readonly source: ListingSource;
  private readonly sourceName: 'dynamodb' | 'demo';
  private loadPromise?: Promise<void>;
  private refreshPromise?: Promise<void>;
  private timer?: ReturnType<typeof setInterval>;
  private state: CacheStatus['state'] = 'idle';
  private lastRefreshAt: string | null = null;
  private error?: string;

  constructor(source?: ListingSource, sourceName?: CacheStatus['source']) {
    const useDemoData = process.env.WYNNMARKET_USE_DEMO_DATA === 'true';
    this.source = source ?? (useDemoData ? new DemoListingSource() : new DynamoListingSource());
    this.sourceName = sourceName ?? (useDemoData ? 'demo' : 'dynamodb');
  }

  async ensureReady(): Promise<void> {
    if (this.state === 'ready') return;
    if (this.loadPromise) return this.loadPromise;

    this.state = 'loading';
    this.loadPromise = this.source.scanAll((listings) => this.index.addListings(listings))
      .then(() => {
        this.state = 'ready';
        this.error = undefined;
        this.lastRefreshAt = new Date().toISOString();
        this.startRefreshTimer();
      })
      .catch((error: unknown) => {
        this.state = 'error';
        this.error = error instanceof Error ? error.message : 'Unable to load market data';
        this.loadPromise = undefined;
        throw error;
      });

    return this.loadPromise;
  }

  async refresh(): Promise<void> {
    await this.ensureReady();
    if (this.refreshPromise) return this.refreshPromise;

    const itemTypes = [...new Set([...KNOWN_ITEM_TYPES, ...this.index.getItemTypes()])];
    this.refreshPromise = Promise.all(itemTypes.map(async (itemType) => {
      const latestKey = this.index.getLatestKey(itemType) ?? '';
      this.index.addListings(await this.source.queryAfter(itemType, latestKey));
    }))
      .then(() => {
        this.lastRefreshAt = new Date().toISOString();
        this.error = undefined;
      })
      .catch((error: unknown) => {
        this.error = error instanceof Error ? error.message : 'Unable to refresh market data';
      })
      .finally(() => {
        this.refreshPromise = undefined;
      });

    return this.refreshPromise;
  }

  getCatalog() {
    return this.index.getCatalog();
  }

  getHistory(id: string, range: HistoryRange) {
    return this.index.getHistory(id, range);
  }

  getStatus(): CacheStatus {
    return {
      state: this.state,
      recordCount: this.index.recordCount,
      itemCount: this.index.itemCount,
      lastRefreshAt: this.lastRefreshAt,
      error: this.error,
      source: this.sourceName,
    };
  }

  private startRefreshTimer(): void {
    if (this.timer || this.sourceName === 'demo') return;
    const requestedSeconds = Number(process.env.WYNNMARKET_REFRESH_SECONDS ?? 60);
    const seconds = Number.isFinite(requestedSeconds) ? Math.max(30, requestedSeconds) : 60;
    this.timer = setInterval(() => void this.refresh(), seconds * 1000);
    this.timer.unref?.();
  }
}

const globalCache = globalThis as typeof globalThis & { __wynnMarketCache?: MarketCache };

export const marketCache = globalCache.__wynnMarketCache ?? new MarketCache();

if (process.env.NODE_ENV !== 'production') globalCache.__wynnMarketCache = marketCache;
