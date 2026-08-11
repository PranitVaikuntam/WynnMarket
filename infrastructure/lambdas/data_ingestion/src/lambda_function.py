import json
import os
import traceback
from datetime import datetime
from typing import Any

try:
    import psycopg2
    from psycopg2.extras import Json
except ImportError as exc:
    raise RuntimeError(
        "psycopg2 is required. Provide it with a Lambda layer or package it with the function."
    ) from exc


INSERT_MARKET_ITEM_SQL = """
INSERT INTO market_items (
    player_name,
    mod_version,
    scanned_at,
    item,
    item_type,
    item_fk,
    listing_price,
    amount,
    hash_code
) VALUES (
    %(player_name)s,
    %(mod_version)s,
    %(scanned_at)s,
    %(item)s,
    %(item_type)s,
    %(item_fk)s,
    %(listing_price)s,
    %(amount)s,
    %(hash_code)s
)
RETURNING id;
"""


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    try:
        payload = parse_event(event)
        listing = extract_data(payload)

        with connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(INSERT_MARKET_ITEM_SQL, listing)
                market_item_id = cursor.fetchone()[0]
            connection.commit()

        return response(201, {"id": market_item_id})
    except (json.JSONDecodeError, ValueError) as exc:
        return response(400, {"error": str(exc)})
    except Exception:
        traceback.print_exc()
        return response(500, {"error": "Failed to ingest market item."})


def response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def parse_event(event: dict[str, Any]) -> dict[str, Any]:
    body = event.get("body")

    if body is None:
        return event

    if isinstance(body, str):
        return json.loads(body)

    if isinstance(body, dict):
        return body

    raise ValueError("Lambda event body must be a JSON object or JSON string.")


def extract_data(payload: dict[str, Any]) -> dict[str, Any]:
    try:
        return {
            "player_name": payload["player_name"],
            "mod_version": payload["mod_version"],
            "scanned_at": datetime.fromisoformat(payload["scanned_at"]),
            "item": Json(payload["item"]),
            "item_type": payload["item_type"],
            "item_fk": payload.get("item_fk"),
            "listing_price": payload.get("listing_price"),
            "amount": payload.get("amount"),
            "hash_code": payload.get("hash_code"),
        }
    except KeyError as exc:
        raise ValueError(f"Missing required field: {exc.args[0]}") from exc
    except Exception as exc:
        raise ValueError(f"Invalid data format: {exc}") from exc


def connect():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ["DB_PORT"]),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=5,
    )
