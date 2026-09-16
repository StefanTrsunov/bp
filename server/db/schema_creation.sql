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
    id                uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           uuid           NOT NULL REFERENCES project.users(id)  ON DELETE CASCADE,
    crypto_id         uuid           NOT NULL REFERENCES project.crypto(id),
    quantity          numeric(20,4)  NOT NULL CHECK (quantity >= 0),
    -- Committed to the user's own open sell orders, not yet removed from the
    -- position. quantity - reserved_quantity is what is actually free to
    -- sell — the crypto-side equivalent of users.available_balance.
    reserved_quantity numeric(20,4)  NOT NULL DEFAULT 0
                                      CHECK (reserved_quantity >= 0 AND reserved_quantity <= quantity),
    -- Weighted-average entry price. NOT NULL so that the P/L arithmetic in
    -- v_portfolio can never silently produce NULL for an existing position.
    avg_price         numeric(18,6)  NOT NULL DEFAULT 0 CHECK (avg_price >= 0),
    created_at        timestamptz    NOT NULL DEFAULT now(),
    updated_at        timestamptz,
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
       h.reserved_quantity,
       (h.quantity - h.reserved_quantity) AS available_quantity,
       h.avg_price,
       lp.price                           AS current_price,
       (h.quantity * lp.price)            AS market_value,
       (h.quantity * (lp.price - h.avg_price)) AS unrealized_pnl
FROM   project.holdings h
JOIN   project.crypto   c ON c.id = h.crypto_id
LEFT   JOIN project.markets m ON m.crypto_id = c.id AND m.quote_currency = 'USD'
LEFT   JOIN project.v_latest_prices lp ON lp.market_id = m.id;

-- ============================================================================
-- REPORTS (P6 — Complex DB Reports)
-- Both are single SELECT statements (with CTEs), wrapped as SQL functions so
-- they can be called as parameterised reports from the prototype instead of
-- being copy-pasted SQL text. See docs/P6-AdvancedReports/AdvancedReports.md.
-- ============================================================================

-- report_top_traders: realized trading performance per user over [p_from, p_to),
-- bucketed into quarters to measure how consistently each user was profitable.
CREATE OR REPLACE FUNCTION project.report_top_traders(p_from timestamptz, p_to timestamptz)
RETURNS TABLE (
    username            varchar,
    realized_pl         numeric,
    total_invested      numeric,
    roi_pct             numeric,
    profitable_periods  bigint,
    losing_periods      bigint,
    total_periods       bigint,
    consistency_pct     numeric
)
LANGUAGE sql STABLE AS $$
    WITH period_pl AS (
        SELECT
            t.user_id,
            date_trunc('quarter', t.created_at)          AS period,
            SUM(t.amount)                                AS period_pl,
            SUM(t.amount) FILTER (WHERE t.type = 'buy')  AS period_buy
        FROM project.transactions t
        WHERE t.type IN ('buy', 'sell', 'fee')
          AND t.created_at >= p_from
          AND t.created_at <  p_to
        GROUP BY t.user_id, date_trunc('quarter', t.created_at)
    )
    SELECT
        u.username,
        SUM(pp.period_pl)                                                       AS realized_pl,
        ABS(SUM(pp.period_buy))                                                 AS total_invested,
        ROUND(SUM(pp.period_pl) / NULLIF(ABS(SUM(pp.period_buy)), 0) * 100, 2)  AS roi_pct,
        COUNT(*) FILTER (WHERE pp.period_pl > 0)                                AS profitable_periods,
        COUNT(*) FILTER (WHERE pp.period_pl < 0)                                AS losing_periods,
        COUNT(*)                                                                AS total_periods,
        ROUND(COUNT(*) FILTER (WHERE pp.period_pl > 0)::numeric
              / NULLIF(COUNT(*), 0) * 100, 2)                                   AS consistency_pct
    FROM period_pl pp
    JOIN project.users u ON u.id = pp.user_id
    GROUP BY u.id, u.username
    ORDER BY realized_pl DESC;
$$;

-- report_market_performance: trading activity and price behaviour per market
-- over [p_from, p_to). Volume/trade-count/price stats come from market_trades
-- (the complete tape — user fills and simulated fills alike); participating
-- users can only come from orders, since market_trades has no user_id column.
CREATE OR REPLACE FUNCTION project.report_market_performance(p_from timestamptz, p_to timestamptz)
RETURNS TABLE (
    symbol               varchar,
    quote_currency       char(3),
    total_volume         numeric,
    trade_count          bigint,
    avg_price            numeric,
    market_return_pct    numeric,
    price_volatility     numeric,
    participating_users  bigint
)
LANGUAGE sql STABLE AS $$
    WITH trades AS (
        SELECT
            market_id, price, quantity, executed_at,
            FIRST_VALUE(price) OVER w AS first_price,
            LAST_VALUE(price)  OVER (PARTITION BY market_id ORDER BY executed_at
                                      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_price
        FROM project.market_trades
        WHERE executed_at >= p_from AND executed_at < p_to
        WINDOW w AS (PARTITION BY market_id ORDER BY executed_at)
    ),
    market_stats AS (
        SELECT
            market_id,
            SUM(quantity)    AS total_volume,
            COUNT(*)         AS trade_count,
            AVG(price)       AS avg_price,
            STDDEV(price)    AS price_volatility,
            MAX(first_price) AS first_price,
            MAX(last_price)  AS last_price
        FROM trades
        GROUP BY market_id
    ),
    participation AS (
        SELECT market_id, COUNT(DISTINCT user_id) AS participating_users
        FROM project.orders
        WHERE status = 'executed' AND executed_at >= p_from AND executed_at < p_to
        GROUP BY market_id
    )
    SELECT
        c.symbol,
        m.quote_currency,
        ms.total_volume,
        ms.trade_count,
        ROUND(ms.avg_price, 6)                                                            AS avg_price,
        ROUND((ms.last_price - ms.first_price) / NULLIF(ms.first_price, 0) * 100, 2)      AS market_return_pct,
        ROUND(COALESCE(ms.price_volatility, 0), 6)                                        AS price_volatility,
        COALESCE(p.participating_users, 0)                                                AS participating_users
    FROM market_stats ms
    JOIN project.markets m ON m.id = ms.market_id
    JOIN project.crypto  c ON c.id = m.crypto_id
    LEFT JOIN participation p ON p.market_id = ms.market_id
    ORDER BY ms.total_volume DESC;
$$;
