import { describe, expect, it } from 'vitest';
import { MarketIndex, createItemId, type RawListing } from './market';

function listing(overrides: Partial<RawListing> = {}): RawListing {
  return {
    pk: 'MaterialItem',
    sk: '2026-08-30T12:00:00.000Z_0',
    timestamp: '2026-08-30T12:00:00.000Z',
    amount: 4,
    listingPrice: 200,
    item: {
      name: 'Dernic Ingot',
      itemType: 'MaterialItem',
      type: 'DernicIngot',
      rarity: 'Common',
      tier: 3,
    },
    ...overrides,
  };
}

describe('MarketIndex', () => {
  it('merges case-only name variants but keeps tiers separate', () => {
    const index = new MarketIndex();
    index.addListings([
      listing(),
      listing({
        sk: '2026-08-30T12:05:00.000Z_0',
        timestamp: '2026-08-30T12:05:00.000Z',
        item: { ...listing().item, name: 'dernic ingot' },
      }),
      listing({
        sk: '2026-08-30T12:10:00.000Z_0',
        timestamp: '2026-08-30T12:10:00.000Z',
        item: { ...listing().item, tier: 2 },
      }),
    ]);

    expect(index.getCatalog()).toHaveLength(2);
    expect(index.getCatalog().find((item) => item.tier === 3)?.observationCount).toBe(2);
  });

  it('deduplicates repeated primary keys', () => {
    const index = new MarketIndex();
    expect(index.addListings([listing(), listing()])).toBe(1);
    expect(index.recordCount).toBe(1);
  });

  it('calculates range summaries and chronological buckets', () => {
    const index = new MarketIndex();
    index.addListings([
      listing({ listingPrice: 100, amount: 2 }),
      listing({ sk: '2026-08-30T13:00:00.000Z_0', timestamp: '2026-08-30T13:00:00.000Z', listingPrice: 200, amount: 3 }),
      listing({ sk: '2026-08-30T14:00:00.000Z_0', timestamp: '2026-08-30T14:00:00.000Z', listingPrice: 300, amount: 5 }),
    ]);

    const history = index.getHistory(
      createItemId('MaterialItem', 'Dernic Ingot', 3),
      '24h',
      Date.parse('2026-08-30T15:00:00.000Z'),
    );

    expect(history?.summary).toMatchObject({
      latestPrice: 300,
      lowestPrice: 100,
      medianPrice: 200,
      observedVolume: 10,
      observationCount: 3,
    });
    expect(history?.series.map((point) => point.medianPrice)).toEqual([100, 200, 300]);
  });
});
