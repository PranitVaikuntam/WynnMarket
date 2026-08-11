CREATE TABLE IF NOT EXISTS market_items (
    id BIGSERIAL PRIMARY KEY,

    player_name TEXT NULL,
    mod_version TEXT NOT NULL,
    scanned_at TIMESTAMPTZ NOT NULL,

    item JSONB NOT NULL,
    item_type TEXT NOT NULL,
    item_fk BIGINT NULL,

    listing_price BIGINT NOT NULL,
    amount INTEGER NOT NULL,
    hash_code BIGINT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT market_items_item_type_check
        CHECK (item_type IN ('GEAR', 'SIMPLE_ITEM', 'TIER')),

    CONSTRAINT market_items_listing_price_nonnegative
        CHECK (listing_price >= 0),

    CONSTRAINT market_items_amount_nonnegative
        CHECK (amount >= 0)
);