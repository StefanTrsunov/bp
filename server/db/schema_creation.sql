-- schema_creation.sql
-- EduBerza - crypto exchange simulation database
-- Course: Databases 2025/2026 Winter, FINKI UKIM
--
-- This script is idempotent. It drops the `project` schema and all contained
-- objects, then recreates them from scratch. Safe to run on an empty database
-- or on a database where the schema already exists.

DROP SCHEMA IF EXISTS project CASCADE;
CREATE SCHEMA project;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

SET search_path TO project, public;

-- ============================================================================
-- USERS
-- Platform users. Each user has virtual (prop) balances used for simulation.
-- ============================================================================
CREATE TABLE project.users (
    id                uuid            PRIMARY KEY DEFAULT gen_random_uuid(),
    username          varchar(50)     NOT NULL UNIQUE,
    email             varchar(255)    NOT NULL UNIQUE,
    full_name         varchar(200),
    password_hash     varchar(255)    NOT NULL,
    available_balance numeric(18,4)   NOT NULL DEFAULT 0 CHECK (available_balance >= 0),
    invested_balance  numeric(18,4)   NOT NULL DEFAULT 0 CHECK (invested_balance  >= 0),
    created_at        timestamptz     NOT NULL DEFAULT now(),
    updated_at        timestamptz
);

-- ============================================================================
-- CRYPTO
-- Catalog of crypto assets available on the platform.
-- ============================================================================
CREATE TABLE project.crypto (
    id         uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    symbol     varchar(20)  NOT NULL UNIQUE,
    name       varchar(255) NOT NULL,
    created_at timestamptz  NOT NULL DEFAULT now()
);

-- ============================================================================
-- MARKETS
-- A market is a (crypto, quote_currency) pair, e.g. BTC/USD.
-- ============================================================================
CREATE TABLE project.markets (
    id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    crypto_id      uuid        NOT NULL REFERENCES project.crypto(id),
    quote_currency char(3)     NOT NULL DEFAULT 'USD',
    is_active      boolean     NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_markets UNIQUE (crypto_id, quote_currency)
);

-- ============================================================================
-- HOLDINGS
-- Per-user crypto position with running weighted average entry price.
-- ============================================================================
CREATE TABLE project.holdings (
    id         uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid           NOT NULL REFERENCES project.users(id)  ON DELETE CASCADE,
    crypto_id  uuid           NOT NULL REFERENCES project.crypto(id),
    quantity   numeric(20,4)  NOT NULL CHECK (quantity >= 0),
    -- Weighted-average entry price. NOT NULL so that the P/L arithmetic in
    -- v_portfolio can never silently produce NULL for an existing position.
    avg_price  numeric(18,6)  NOT NULL DEFAULT 0 CHECK (avg_price >= 0),
    created_at timestamptz    NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT uq_holdings_user_crypto UNIQUE (user_id, crypto_id)
);

-- ============================================================================
-- ORDERS
-- Orders placed by users on a market.
-- ============================================================================
CREATE TABLE project.orders (
    id          uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid           NOT NULL REFERENCES project.users(id)   ON DELETE CASCADE,
    market_id   uuid           NOT NULL REFERENCES project.markets(id),
    side        varchar(4)     NOT NULL CHECK (side   IN ('buy', 'sell')),
    type        varchar(20)    NOT NULL CHECK (type   IN ('market', 'limit')),
    status      varchar(20)    NOT NULL CHECK (status IN ('open', 'executed', 'cancelled')),
    quantity    numeric(20,4)  NOT NULL CHECK (quantity > 0),
    price       numeric(18,6),
    placed_at   timestamptz    NOT NULL DEFAULT now(),
    executed_at timestamptz
);

CREATE INDEX idx_orders_user      ON project.orders(user_id);
CREATE INDEX idx_orders_market    ON project.orders(market_id);
CREATE INDEX idx_orders_status    ON project.orders(status);

-- ============================================================================
-- TRANSACTIONS
-- Financial ledger: deposits, buys, sells, fees.
-- ============================================================================
CREATE TABLE project.transactions (
    id            uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid           NOT NULL REFERENCES project.users(id) ON DELETE CASCADE,
    type          varchar(50)    NOT NULL CHECK (type IN ('deposit', 'buy', 'sell', 'fee')),
    amount        numeric(18,4)  NOT NULL,
    currency      char(3)        NOT NULL DEFAULT 'USD',
    related_order uuid           REFERENCES project.orders(id),
    created_at    timestamptz    NOT NULL DEFAULT now(),
    description   text
);

CREATE INDEX idx_transactions_user ON project.transactions(user_id, created_at DESC);

-- ============================================================================
-- MARKET TRADES
-- Raw executed trades on a market. Source of truth for current price.
-- ============================================================================
CREATE TABLE project.market_trades (
    id          bigserial      PRIMARY KEY,
    market_id   uuid           NOT NULL REFERENCES project.markets(id),
    executed_at timestamptz    NOT NULL,
    price       numeric(18,6)  NOT NULL CHECK (price    > 0),
    quantity    numeric(20,6)  NOT NULL CHECK (quantity > 0),
    side        varchar(4)     CHECK (side IN ('buy', 'sell')),
    source      varchar(50)    NOT NULL DEFAULT 'simulation'
);

CREATE INDEX idx_market_trades_market_time ON project.market_trades(market_id, executed_at DESC);

-- ============================================================================
-- MARKET CANDLES
-- OHLCV aggregates over standard timeframes.
-- ============================================================================
CREATE TABLE project.market_candles (
    id          bigserial      PRIMARY KEY,
    market_id   uuid           NOT NULL REFERENCES project.markets(id),
    timeframe   varchar(5)     NOT NULL CHECK (timeframe IN ('1m', '5m', '1h', '1d')),
    open        numeric(18,6)  NOT NULL,
    high        numeric(18,6)  NOT NULL,
    low         numeric(18,6)  NOT NULL,
    close       numeric(18,6)  NOT NULL,
    volume      numeric(20,6)  NOT NULL,
    candle_time timestamptz    NOT NULL,
    CONSTRAINT uq_candle UNIQUE (market_id, timeframe, candle_time)
);

CREATE INDEX idx_market_candles_market_tf_time ON project.market_candles(market_id, timeframe, candle_time DESC);

-- ============================================================================
-- WATCHLISTS
-- ============================================================================
CREATE TABLE project.watchlists (
    id         uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid         NOT NULL REFERENCES project.users(id) ON DELETE CASCADE,
    name       varchar(100) NOT NULL,
    created_at timestamptz  NOT NULL DEFAULT now()
);

CREATE TABLE project.watchlist_items (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    watchlist_id uuid        NOT NULL REFERENCES project.watchlists(id) ON DELETE CASCADE,
    crypto_id    uuid        NOT NULL REFERENCES project.crypto(id),
    added_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_watchlist_crypto UNIQUE (watchlist_id, crypto_id)
);

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Latest trade price per market (current price).
CREATE OR REPLACE VIEW project.v_latest_prices AS
SELECT DISTINCT ON (t.market_id)
       t.market_id,
       c.symbol,
       m.quote_currency,
       t.price,
       t.executed_at
FROM   project.market_trades t
JOIN   project.markets       m ON m.id = t.market_id
JOIN   project.crypto        c ON c.id = m.crypto_id
ORDER  BY t.market_id, t.executed_at DESC;

-- Portfolio valuation per user (holdings x latest price).
CREATE OR REPLACE VIEW project.v_portfolio AS
SELECT h.user_id,
       c.symbol,
       h.quantity,
       h.avg_price,
       lp.price                           AS current_price,
       (h.quantity * lp.price)            AS market_value,
       (h.quantity * (lp.price - h.avg_price)) AS unrealized_pnl
FROM   project.holdings h
JOIN   project.crypto   c ON c.id = h.crypto_id
LEFT   JOIN project.markets m ON m.crypto_id = c.id AND m.quote_currency = 'USD'
LEFT   JOIN project.v_latest_prices lp ON lp.market_id = m.id;
