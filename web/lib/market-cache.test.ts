import { describe, expect, it } from 'vitest';
import { parseDynamoListing } from './market-cache';

describe('parseDynamoListing', () => {
  it('parses the nested DynamoDB listing shape', () => {
    const parsed = parseDynamoListing({
      pk: { S: 'PowderItem' },
      sk: { S: '2026-08-30T12:00:00.000Z_1' },
      timestamp: { S: '2026-08-30T12:00:00.000Z' },
      amount: { N: '8' },
      listingPrice: { N: '2048' },
      item: {
        M: {
          name: { S: 'Air Powder' },
          itemType: { S: 'PowderItem' },
          rarity: { S: 'Common' },
          type: { S: 'Air' },
          tier: { N: '6' },
        },
      },
    });

    expect(parsed).toMatchObject({
      pk: 'PowderItem',
      amount: 8,
      listingPrice: 2048,
      item: { name: 'Air Powder', tier: 6 },
    });
  });

  it('rejects incomplete records', () => {
    expect(parseDynamoListing({ pk: { S: 'RuneItem' } })).toBeNull();
  });
});
