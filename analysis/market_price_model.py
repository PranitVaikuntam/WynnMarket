#!/usr/bin/env python3
"""Analyze DynamoDB market listings and forecast per-variant market prices.

The input may be the raw output of `aws dynamodb scan` or a JSON list of
already-decoded records. Listings are aggregated into time buckets before
training so repeated market snapshots are not treated as independent sales.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable


VARIANT_FIELDS = ("itemType", "type", "name", "rarity", "tier")
CAT_FEATURES = ("itemType", "type", "name", "rarity")
NUM_FEATURES = (
    "tier",
    "hour_sin",
    "hour_cos",
    "weekday_sin",
    "weekday_cos",
    "history_count",
    "lag_log_price",
    "rolling_log_median",
    "rolling_log_std",
    "log_price_momentum",
    "lag_log_quantity",
    "lag_listing_count",
    "hours_since_seen",
    "type_log_median",
    "global_log_median",
)
FEATURES = CAT_FEATURES + NUM_FEATURES
ANALYSIS_DIR = Path(__file__).resolve().parent


@dataclass(frozen=True)
class Snapshot:
    timestamp: datetime
    variant: tuple[str, str, str, str, int]
    price: float
    total_quantity: int
    listing_count: int
    minimum_price: float
    maximum_price: float


def decode_attribute(value: Any) -> Any:
    """Decode one DynamoDB AttributeValue recursively."""
    if not isinstance(value, dict) or len(value) != 1:
        return value
    kind, payload = next(iter(value.items()))
    if kind == "S":
        return payload
    if kind == "N":
        number = str(payload)
        return float(number) if any(c in number for c in ".eE") else int(number)
    if kind == "BOOL":
        return bool(payload)
    if kind == "NULL":
        return None
    if kind == "M":
        return {key: decode_attribute(item) for key, item in payload.items()}
    if kind == "L":
        return [decode_attribute(item) for item in payload]
    if kind in {"SS", "NS"}:
        return list(payload)
    return payload


def load_records(path: Path) -> list[dict[str, Any]]:
    raw = json.loads(path.read_text())
    records = raw.get("Items", raw) if isinstance(raw, dict) else raw
    if not isinstance(records, list):
        raise ValueError("Input must be a DynamoDB scan result or a JSON list")
    decoded = []
    for record in records:
        if any(key in value for value in record.values() if isinstance(value, dict) for key in ("S", "N", "M")):
            decoded.append({key: decode_attribute(value) for key, value in record.items()})
        else:
            decoded.append(record)
    return decoded


def parse_timestamp(value: str) -> datetime:
    # Python supports microseconds, while DynamoDB values here contain nanoseconds.
    text = value.rstrip("Z")
    if "." in text:
        head, fraction = text.split(".", 1)
        text = f"{head}.{fraction[:6].ljust(6, '0')}"
    return datetime.fromisoformat(text).replace(tzinfo=timezone.utc)


def floor_time(value: datetime, minutes: int) -> datetime:
    minute = value.minute - value.minute % minutes
    return value.replace(minute=minute, second=0, microsecond=0)


def weighted_median(values: Iterable[tuple[float, int]]) -> float:
    ordered = sorted((price, max(1, quantity)) for price, quantity in values)
    threshold = sum(quantity for _, quantity in ordered) / 2
    cumulative = 0
    for price, quantity in ordered:
        cumulative += quantity
        if cumulative >= threshold:
            return price
    return ordered[-1][0]


def variant_from(record: dict[str, Any]) -> tuple[str, str, str, str, int]:
    item = record.get("item") or {}
    return (
        str(item.get("itemType") or record.get("pk") or "unknown"),
        str(item.get("type") or "unknown"),
        str(item.get("name") or "unknown"),
        str(item.get("rarity") or "unknown"),
        int(item.get("tier") or 0),
    )


def aggregate_snapshots(records: list[dict[str, Any]], bucket_minutes: int) -> list[Snapshot]:
    grouped: dict[tuple[datetime, tuple[str, str, str, str, int]], list[tuple[float, int]]] = defaultdict(list)
    for record in records:
        price = float(record.get("listingPrice", 0))
        quantity = int(record.get("amount", 0))
        timestamp = record.get("timestamp")
        if price <= 0 or quantity <= 0 or not timestamp:
            continue
        key = floor_time(parse_timestamp(str(timestamp)), bucket_minutes), variant_from(record)
        grouped[key].append((price, quantity))

    snapshots = []
    for (timestamp, variant), listings in grouped.items():
        prices = [price for price, _ in listings]
        snapshots.append(
            Snapshot(
                timestamp=timestamp,
                variant=variant,
                price=weighted_median(listings),
                total_quantity=sum(quantity for _, quantity in listings),
                listing_count=len(listings),
                minimum_price=min(prices),
                maximum_price=max(prices),
            )
        )
    return sorted(snapshots, key=lambda snapshot: (snapshot.timestamp, snapshot.variant))


def median_or(values: Iterable[float], fallback: float) -> float:
    materialized = list(values)
    return statistics.median(materialized) if materialized else fallback


def feature_row(
    snapshot: Snapshot,
    variant_history: dict[tuple[str, str, str, str, int], deque[Snapshot]],
    type_history: dict[str, deque[float]],
    global_history: deque[float],
) -> dict[str, Any]:
    history = variant_history[snapshot.variant]
    log_prices = [math.log(item.price) for item in history]
    global_median = median_or(global_history, 0.0)
    type_median = median_or(type_history[snapshot.variant[0]], global_median)
    lag = log_prices[-1] if log_prices else type_median
    rolling = median_or(log_prices[-20:], type_median)
    rolling_std = statistics.pstdev(log_prices[-20:]) if len(log_prices) >= 2 else 0.0
    old_window = log_prices[-20:-10]
    new_window = log_prices[-10:]
    momentum = median_or(new_window, rolling) - median_or(old_window, rolling)
    previous = history[-1] if history else None
    hour = snapshot.timestamp.hour + snapshot.timestamp.minute / 60
    weekday = snapshot.timestamp.weekday()
    item_type, type_name, name, rarity, tier = snapshot.variant
    return {
        "itemType": item_type,
        "type": type_name,
        "name": name,
        "rarity": rarity,
        "tier": tier,
        "hour_sin": math.sin(2 * math.pi * hour / 24),
        "hour_cos": math.cos(2 * math.pi * hour / 24),
        "weekday_sin": math.sin(2 * math.pi * weekday / 7),
        "weekday_cos": math.cos(2 * math.pi * weekday / 7),
        "history_count": len(history),
        "lag_log_price": lag,
        "rolling_log_median": rolling,
        "rolling_log_std": rolling_std,
        "log_price_momentum": momentum,
        "lag_log_quantity": math.log1p(previous.total_quantity) if previous else 0.0,
        "lag_listing_count": previous.listing_count if previous else 0,
        "hours_since_seen": (snapshot.timestamp - previous.timestamp).total_seconds() / 3600 if previous else 168.0,
        "type_log_median": type_median,
        "global_log_median": global_median,
    }


def build_training_rows(snapshots: list[Snapshot]) -> list[dict[str, Any]]:
    variant_history: dict[tuple[str, str, str, str, int], deque[Snapshot]] = defaultdict(lambda: deque(maxlen=100))
    type_history: dict[str, deque[float]] = defaultdict(lambda: deque(maxlen=1000))
    global_history: deque[float] = deque(maxlen=5000)
    rows: list[dict[str, Any]] = []

    # All variants in the same bucket get features before that bucket updates history.
    by_time: dict[datetime, list[Snapshot]] = defaultdict(list)
    for snapshot in snapshots:
        by_time[snapshot.timestamp].append(snapshot)
    for timestamp in sorted(by_time):
        batch = by_time[timestamp]
        for snapshot in batch:
            row = feature_row(snapshot, variant_history, type_history, global_history)
            row["target_log_price"] = math.log(snapshot.price)
            row["timestamp"] = snapshot.timestamp.isoformat()
            row["variant"] = "|".join(map(str, snapshot.variant))
            rows.append(row)
        for snapshot in batch:
            variant_history[snapshot.variant].append(snapshot)
            log_price = math.log(snapshot.price)
            type_history[snapshot.variant[0]].append(log_price)
            global_history.append(log_price)
    return rows


def analysis_report(records: list[dict[str, Any]], snapshots: list[Snapshot]) -> dict[str, Any]:
    prices = [float(record["listingPrice"]) for record in records if float(record.get("listingPrice", 0)) > 0]
    timestamps = [parse_timestamp(str(record["timestamp"])) for record in records if record.get("timestamp")]
    variants = {variant_from(record) for record in records}
    categories: dict[str, int] = defaultdict(int)
    for record in records:
        categories[variant_from(record)[0]] += 1
    return {
        "listing_records": len(records),
        "usable_snapshots": len(snapshots),
        "unique_variants": len(variants),
        "history_start": min(timestamps).isoformat() if timestamps else None,
        "history_end": max(timestamps).isoformat() if timestamps else None,
        "history_hours": round((max(timestamps) - min(timestamps)).total_seconds() / 3600, 2) if timestamps else 0,
        "listing_price": {
            "minimum": min(prices) if prices else None,
            "median": statistics.median(prices) if prices else None,
            "maximum": max(prices) if prices else None,
        },
        "records_by_category": dict(sorted(categories.items(), key=lambda item: (-item[1], item[0]))),
    }


def matrix(rows: list[dict[str, Any]]) -> list[list[Any]]:
    return [[row[name] for name in FEATURES] for row in rows]


def train_model(rows: list[dict[str, Any]], model_dir: Path, iterations: int) -> dict[str, Any]:
    try:
        from catboost import CatBoostRegressor
    except ImportError as exc:
        raise SystemExit("CatBoost is required for training. Install dependencies with: pip install -r requirements.txt") from exc

    if len(rows) < 100:
        raise SystemExit(f"Only {len(rows)} aggregated observations are available; at least 100 are required")
    rows = sorted(rows, key=lambda row: row["timestamp"])
    timestamps = sorted({row["timestamp"] for row in rows})
    split_timestamp = timestamps[max(1, int(len(timestamps) * 0.8))]
    train = [row for row in rows if row["timestamp"] < split_timestamp]
    test = [row for row in rows if row["timestamp"] >= split_timestamp]
    categorical_indices = list(range(len(CAT_FEATURES)))
    train_x, test_x = matrix(train), matrix(test)
    train_y = [row["target_log_price"] for row in train]
    test_y = [row["target_log_price"] for row in test]
    model_dir.mkdir(parents=True, exist_ok=True)

    models = {}
    for label, alpha in (("low", 0.1), ("median", 0.5), ("high", 0.9)):
        model = CatBoostRegressor(
            loss_function=f"Quantile:alpha={alpha}",
            iterations=iterations,
            depth=8,
            learning_rate=0.05,
            l2_leaf_reg=5,
            random_seed=42,
            verbose=False,
            allow_writing_files=False,
        )
        model.fit(train_x, train_y, cat_features=categorical_indices)
        model.save_model(str(model_dir / f"price_{label}.cbm"))
        models[label] = model

    predicted_log = models["median"].predict(test_x)
    actual = [math.exp(value) for value in test_y]
    predicted = [math.exp(value) for value in predicted_log]
    absolute_errors = [abs(p - a) for p, a in zip(predicted, actual)]
    percentage_errors = [abs(p - a) / a for p, a in zip(predicted, actual)]
    baseline = [math.exp(row["rolling_log_median"]) for row in test]
    baseline_percentage_errors = [abs(p - a) / a for p, a in zip(baseline, actual)]
    metrics = {
        "training_observations": len(train),
        "test_observations": len(test),
        "split_timestamp": split_timestamp,
        "model_mae": round(statistics.mean(absolute_errors), 3),
        "model_median_absolute_percentage_error": round(statistics.median(percentage_errors), 4),
        "baseline_median_absolute_percentage_error": round(statistics.median(baseline_percentage_errors), 4),
    }
    (model_dir / "metadata.json").write_text(json.dumps({"features": FEATURES, "metrics": metrics}, indent=2) + "\n")
    return {"models": models, "metrics": metrics}


def latest_forecast_rows(snapshots: list[Snapshot]) -> list[dict[str, Any]]:
    variant_history: dict[tuple[str, str, str, str, int], deque[Snapshot]] = defaultdict(lambda: deque(maxlen=100))
    type_history: dict[str, deque[float]] = defaultdict(lambda: deque(maxlen=1000))
    global_history: deque[float] = deque(maxlen=5000)
    for snapshot in snapshots:
        variant_history[snapshot.variant].append(snapshot)
        value = math.log(snapshot.price)
        type_history[snapshot.variant[0]].append(value)
        global_history.append(value)
    forecast_time = max(snapshot.timestamp for snapshot in snapshots) + timedelta(minutes=5)
    rows = []
    for variant, history in variant_history.items():
        placeholder = Snapshot(forecast_time, variant, history[-1].price, 0, 0, 0, 0)
        row = feature_row(placeholder, variant_history, type_history, global_history)
        row["variant"] = "|".join(map(str, variant))
        rows.append(row)
    return rows


def write_forecasts(path: Path, rows: list[dict[str, Any]], models: dict[str, Any]) -> None:
    predictions = {label: model.predict(matrix(rows)) for label, model in models.items()}
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["variant", "low_price", "predicted_price", "high_price", "history_count"])
        writer.writeheader()
        for index, row in enumerate(rows):
            low, median, high = (math.exp(predictions[label][index]) for label in ("low", "median", "high"))
            writer.writerow({
                "variant": row["variant"],
                "low_price": round(min(low, median), 2),
                "predicted_price": round(median, 2),
                "high_price": round(max(high, median), 2),
                "history_count": row["history_count"],
            })


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=ANALYSIS_DIR / "data" / "trade_market_listings.json")
    parser.add_argument("--output-dir", type=Path, default=ANALYSIS_DIR / "output")
    parser.add_argument("--bucket-minutes", type=int, default=5)
    parser.add_argument("--iterations", type=int, default=600)
    parser.add_argument("--analyze-only", action="store_true")
    args = parser.parse_args()
    if args.bucket_minutes <= 0:
        parser.error("--bucket-minutes must be positive")

    records = load_records(args.input)
    snapshots = aggregate_snapshots(records, args.bucket_minutes)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    report = analysis_report(records, snapshots)
    (args.output_dir / "analysis.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if args.analyze_only:
        return

    rows = build_training_rows(snapshots)
    result = train_model(rows, args.output_dir, args.iterations)
    forecasts = latest_forecast_rows(snapshots)
    write_forecasts(args.output_dir / "forecasts.csv", forecasts, result["models"])
    print(json.dumps(result["metrics"], indent=2))
    print(f"Saved {len(forecasts)} forecasts to {args.output_dir / 'forecasts.csv'}")


if __name__ == "__main__":
    main()
