import type { RawListing } from './market';

const DEMO_ITEMS = [
  ['MaterialItem', 'Dernic Ingot', 3, 1880],
  ['AmplifierItem', 'Corkian Amplifier', 4, 8420],
  ['PowderItem', 'Air Powder', 6, 14280],
  ['RuneItem', 'Nii Rune', undefined, 482],
  ['EmeraldPouchItem', 'Emerald Pouch', 10, 32400],
  ['IngredientItem', 'Corrupted Fragment', 2, 975],
] as const;

export function createDemoListings(now = Date.now()): RawListing[] {
  return DEMO_ITEMS.flatMap(([itemType, name, tier, basePrice], itemIndex) =>
    Array.from({ length: 48 }, (_, observationIndex) => {
      const timestamp = new Date(now - (47 - observationIndex) * 3 * 60 * 60 * 1000);
      const wave = Math.sin((observationIndex + itemIndex) / 4) * basePrice * 0.08;
      const trend = (23 - observationIndex) * basePrice * 0.002;
      return {
        pk: itemType,
        sk: `${timestamp.toISOString()}_${itemIndex}`,
        timestamp: timestamp.toISOString(),
        amount: 1 + ((observationIndex + itemIndex) % 12),
        listingPrice: Math.max(1, Math.round(basePrice + wave + trend)),
        item: {
          name,
          itemType,
          type: name.replace(/\s+/g, ''),
          rarity: itemType === 'IngredientItem' ? 'Rare' : 'Common',
          tier,
        },
      };
    }),
  );
}
