-- data_load.sql
-- EduBerza - sample data
-- Course: Databases 2025/2026 Winter, FINKI UKIM
--
-- Idempotent. Truncates all tables in the `project` schema and reloads
-- deterministic sample data. Run schema_creation.sql first if tables do
-- not yet exist.
--
-- All sample users have the password: test123

SET search_path TO project, public;

TRUNCATE TABLE
    project.watchlist_items,
    project.watchlists,
    project.market_candles,
    project.market_trades,
    project.transactions,
    project.orders,
    project.holdings,
    project.markets,
    project.crypto,
    project.users
RESTART IDENTITY CASCADE;

-- ============================================================================
-- CRYPTO
-- ============================================================================
INSERT INTO project.crypto (id, symbol, name) VALUES
    ('11111111-1111-1111-1111-111111111111', 'BTC',  'Bitcoin'),
    ('22222222-2222-2222-2222-222222222222', 'ETH',  'Ethereum'),
    ('33333333-3333-3333-3333-333333333333', 'ADA',  'Cardano'),
    ('44444444-4444-4444-4444-444444444444', 'SOL',  'Solana'),
    ('55555555-5555-5555-5555-555555555555', 'DOGE', 'Dogecoin');

-- ============================================================================
-- MARKETS (all quoted in USD)
-- ============================================================================
INSERT INTO project.markets (id, crypto_id, quote_currency, is_active) VALUES
    ('a1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'USD', true),
    ('a2222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'USD', true),
    ('a3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'USD', true),
    ('a4444444-4444-4444-4444-444444444444', '44444444-4444-4444-4444-444444444444', 'USD', true),
    ('a5555555-5555-5555-5555-555555555555', '55555555-5555-5555-5555-555555555555', 'USD', true);

-- ============================================================================
-- USERS
-- Password for all: test123 (stored as sha256 hex hash)
-- ============================================================================
INSERT INTO project.users (id, username, email, full_name, password_hash, available_balance, invested_balance) VALUES
    ('b1111111-1111-1111-1111-111111111111', 'alice',   'alice@example.com',   'Alice Johnson',
        encode(digest('test123', 'sha256'), 'hex'), 10000.0000, 0),
    ('b2222222-2222-2222-2222-222222222222', 'bob',     'bob@example.com',     'Bob Smith',
        encode(digest('test123', 'sha256'), 'hex'),  5000.0000, 0),
    ('b3333333-3333-3333-3333-333333333333', 'charlie', 'charlie@example.com', 'Charlie Davis',
        encode(digest('test123', 'sha256'), 'hex'),  2500.0000, 0);

-- ============================================================================
-- MARKET TRADES
-- Recent simulated trades per market, used as price source.
-- ============================================================================
INSERT INTO project.market_trades (market_id, executed_at, price, quantity, side, source) VALUES
    -- BTC/USD around $67,000
    ('a1111111-1111-1111-1111-111111111111', now() - interval '10 min', 66850.250000, 0.120000, 'buy',  'simulation'),
    ('a1111111-1111-1111-1111-111111111111', now() - interval  '8 min', 66910.500000, 0.075000, 'sell', 'simulation'),
    ('a1111111-1111-1111-1111-111111111111', now() - interval  '5 min', 67020.750000, 0.200000, 'buy',  'simulation'),
    ('a1111111-1111-1111-1111-111111111111', now() - interval  '2 min', 67105.100000, 0.050000, 'buy',  'simulation'),
    ('a1111111-1111-1111-1111-111111111111', now() - interval '30 second', 67140.000000, 0.030000, 'sell', 'simulation'),
    -- ETH/USD around $3,500
    ('a2222222-2222-2222-2222-222222222222', now() - interval '10 min', 3490.500000, 1.500000, 'buy',  'simulation'),
    ('a2222222-2222-2222-2222-222222222222', now() - interval  '6 min', 3502.750000, 0.800000, 'sell', 'simulation'),
    ('a2222222-2222-2222-2222-222222222222', now() - interval  '2 min', 3515.250000, 2.100000, 'buy',  'simulation'),
    ('a2222222-2222-2222-2222-222222222222', now() - interval '30 second', 3520.000000, 0.650000, 'buy',  'simulation'),
    -- ADA/USD around $0.45
    ('a3333333-3333-3333-3333-333333333333', now() - interval '10 min', 0.446500,  500.000000, 'buy',  'simulation'),
    ('a3333333-3333-3333-3333-333333333333', now() - interval  '3 min', 0.452000, 1200.000000, 'buy',  'simulation'),
    ('a3333333-3333-3333-3333-333333333333', now() - interval '30 second', 0.453750,  800.000000, 'sell', 'simulation'),
    -- SOL/USD around $165
    ('a4444444-4444-4444-4444-444444444444', now() - interval '10 min', 164.250000, 10.000000, 'buy',  'simulation'),
    ('a4444444-4444-4444-4444-444444444444', now() - interval  '4 min', 165.500000,  5.500000, 'sell', 'simulation'),
    ('a4444444-4444-4444-4444-444444444444', now() - interval '30 second', 166.100000,  8.000000, 'buy',  'simulation'),
    -- DOGE/USD around $0.12
    ('a5555555-5555-5555-5555-555555555555', now() - interval '10 min', 0.118500, 10000.000000, 'buy',  'simulation'),
    ('a5555555-5555-5555-5555-555555555555', now() - interval  '3 min', 0.121250,  7500.000000, 'sell', 'simulation'),
    ('a5555555-5555-5555-5555-555555555555', now() - interval '30 second', 0.122000, 12000.000000, 'buy',  'simulation');

-- ============================================================================
-- MARKET CANDLES (1h aggregates, last 5 hours per market)
-- ============================================================================
INSERT INTO project.market_candles (market_id, timeframe, open, high, low, close, volume, candle_time) VALUES
    ('a1111111-1111-1111-1111-111111111111', '1h', 66200, 66500, 66050, 66400, 12.50, date_trunc('hour', now() - interval '5 hour')),
    ('a1111111-1111-1111-1111-111111111111', '1h', 66400, 66800, 66380, 66700, 15.30, date_trunc('hour', now() - interval '4 hour')),
    ('a1111111-1111-1111-1111-111111111111', '1h', 66700, 66950, 66650, 66900, 11.80, date_trunc('hour', now() - interval '3 hour')),
    ('a1111111-1111-1111-1111-111111111111', '1h', 66900, 67100, 66800, 67050, 14.20, date_trunc('hour', now() - interval '2 hour')),
    ('a1111111-1111-1111-1111-111111111111', '1h', 67050, 67200, 66900, 67140, 10.75, date_trunc('hour', now() - interval '1 hour')),
    ('a2222222-2222-2222-2222-222222222222', '1h',  3460,  3490,  3450,  3485, 120.0, date_trunc('hour', now() - interval '5 hour')),
    ('a2222222-2222-2222-2222-222222222222', '1h',  3485,  3510,  3480,  3500, 135.0, date_trunc('hour', now() - interval '4 hour')),
    ('a2222222-2222-2222-2222-222222222222', '1h',  3500,  3520,  3495,  3515, 110.0, date_trunc('hour', now() - interval '3 hour')),
    ('a2222222-2222-2222-2222-222222222222', '1h',  3515,  3525,  3500,  3520, 125.5, date_trunc('hour', now() - interval '2 hour')),
    ('a2222222-2222-2222-2222-222222222222', '1h',  3520,  3530,  3510,  3520, 140.0, date_trunc('hour', now() - interval '1 hour'));

-- ============================================================================
-- EXAMPLE ORDERS, HOLDINGS AND TRANSACTIONS for alice
-- Shows a fully-filled market buy and its resulting holding & ledger entry.
-- ============================================================================
INSERT INTO project.orders (id, user_id, market_id, side, type, status, quantity, price, placed_at, executed_at) VALUES
    ('c1111111-1111-1111-1111-111111111111',
     'b1111111-1111-1111-1111-111111111111',
     'a2222222-2222-2222-2222-222222222222',
     'buy', 'market', 'executed', 0.5000, 3500.000000,
     now() - interval '1 hour', now() - interval '1 hour');

INSERT INTO project.holdings (user_id, crypto_id, quantity, avg_price, updated_at) VALUES
    ('b1111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222',
     0.5000, 3500.000000, now() - interval '1 hour');

INSERT INTO project.transactions (user_id, type, amount, currency, related_order, description) VALUES
    ('b1111111-1111-1111-1111-111111111111', 'deposit',  10000.0000, 'USD', NULL,
        'Initial virtual deposit'),
    ('b1111111-1111-1111-1111-111111111111', 'buy',      -1750.0000, 'USD',
        'c1111111-1111-1111-1111-111111111111',
        'Market buy 0.5 ETH @ 3500.00');

-- After the buy, alice's invested_balance reflects the used funds.
UPDATE project.users
   SET available_balance = 10000.0000 - 1750.0000,
       invested_balance  = 1750.0000,
       updated_at        = now()
 WHERE id = 'b1111111-1111-1111-1111-111111111111';

-- ============================================================================
-- WATCHLISTS
-- ============================================================================
INSERT INTO project.watchlists (id, user_id, name) VALUES
    ('d1111111-1111-1111-1111-111111111111', 'b1111111-1111-1111-1111-111111111111', 'Favorites'),
    ('d2222222-2222-2222-2222-222222222222', 'b2222222-2222-2222-2222-222222222222', 'Bobs Picks');

INSERT INTO project.watchlist_items (watchlist_id, crypto_id) VALUES
    ('d1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111'),
    ('d1111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
    ('d1111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444'),
    ('d2222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111'),
    ('d2222222-2222-2222-2222-222222222222', '55555555-5555-5555-5555-555555555555');
