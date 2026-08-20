import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from market_price_model import (
    Snapshot,
    aggregate_snapshots,
    build_training_rows,
    load_records,
    weighted_median,
)


class MarketPriceModelTests(unittest.TestCase):
    def test_decodes_dynamodb_scan(self):
        payload = {
            "Items": [{
                "amount": {"N": "3"},
                "listingPrice": {"N": "125.5"},
                "item": {"M": {"name": {"S": "Test Item"}}},
            }]
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "scan.json"
            path.write_text(json.dumps(payload))
            records = load_records(path)
        self.assertEqual(records[0]["amount"], 3)
        self.assertEqual(records[0]["listingPrice"], 125.5)
        self.assertEqual(records[0]["item"]["name"], "Test Item")

    def test_quantity_weighted_median(self):
        self.assertEqual(weighted_median([(100, 1), (200, 10), (1000, 1)]), 200)

    def test_aggregation_uses_variant_and_time_bucket(self):
        base = {
            "pk": "MaterialItem",
            "amount": 1,
            "item": {
                "itemType": "MaterialItem",
                "type": "Material",
                "name": "Wood",
                "rarity": "Common",
                "tier": 1,
            },
        }
        records = [
            {**base, "listingPrice": 100, "timestamp": "2026-08-15T12:01:00Z"},
            {**base, "listingPrice": 200, "amount": 3, "timestamp": "2026-08-15T12:04:00Z"},
        ]
        snapshots = aggregate_snapshots(records, 5)
        self.assertEqual(len(snapshots), 1)
        self.assertEqual(snapshots[0].price, 200)
        self.assertEqual(snapshots[0].total_quantity, 4)

    def test_same_timestamp_cannot_leak_into_lag_features(self):
        timestamp = datetime(2026, 8, 15, 12, tzinfo=timezone.utc)
        first = Snapshot(timestamp, ("MaterialItem", "A", "A", "Common", 1), 100, 1, 1, 100, 100)
        second = Snapshot(timestamp, ("MaterialItem", "B", "B", "Common", 1), 1000, 1, 1, 1000, 1000)
        rows = build_training_rows([first, second])
        self.assertEqual(rows[0]["history_count"], 0)
        self.assertEqual(rows[1]["history_count"], 0)
        self.assertEqual(rows[0]["global_log_median"], 0.0)
        self.assertEqual(rows[1]["global_log_median"], 0.0)


if __name__ == "__main__":
    unittest.main()
