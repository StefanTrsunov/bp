-- reports_demo_data.sql
-- EduBerza - optional historical data for the P6 reports
-- Course: Databases 2025/2026 Winter, FINKI UKIM
--
-- data_load.sql only seeds ~10 minutes of trade history, which is enough to
-- demonstrate UC0001-UC0007 but not enough to show report_top_traders() or
-- report_market_performance() doing anything interesting: everything falls
-- into a single quarter, so "number of profitable periods" and "consistency"
-- are trivial and "market return" has almost no history to work with.
--
-- This script adds five quarters of synthetic transactions, market trades and
-- executed orders on top of an already-loaded data_load.sql, spanning
-- 2025-07 to 2026-07, so the two P6 reports have several periods and two
-- markets with opposite price trends to actually compare.
--
-- Deliberately NOT part of -init / -load-data: it only inserts into
-- transactions, market_trades and orders, and does not touch
-- users.available_balance/invested_balance or holdings, so it does not
-- disturb the balances the other use cases' documented "verified run"
-- sections depend on. Run it by hand, after data_load.sql, only to exercise
-- the two reports:
--
--   psql "$DATABASE_URL" -f server/db/schema_creation.sql
--   psql "$DATABASE_URL" -f server/db/data_load.sql
--   psql "$DATABASE_URL" -f server/db/reports_demo_data.sql
--
-- Idempotent: deletes its own previously-inserted rows (tagged via
-- description/source) before re-inserting.

-- P7: users' cash (available + reserved) must equal their ledger at
-- COMMIT, so the balance moves by exactly what this script removes and
-- re-adds to the ledger, all in one transaction. The historical orders are
-- imported as completely filled.

BEGIN;

SET search_path TO project, public;

UPDATE users u
   SET available_balance = u.available_balance - d.total
  FROM (SELECT user_id, SUM(amount) AS total FROM transactions
         WHERE description = 'P6 demo data' GROUP BY user_id) d
 WHERE u.id = d.user_id;

DELETE FROM transactions  WHERE description = 'P6 demo data';
DELETE FROM orders        WHERE id IN (
    'e1111111-1111-1111-1111-111111111111', 'e2222222-2222-2222-2222-222222222222',
    'e3333333-3333-3333-3333-333333333333', 'e4444444-4444-4444-4444-444444444444',
    'e5555555-5555-5555-5555-555555555555'
);
DELETE FROM market_trades WHERE source = 'p6_demo';

-- ============================================================================
-- Alice: five quarterly round trips, 3 profitable / 2 losing (60% consistency)
-- ============================================================================
INSERT INTO transactions (user_id, type, amount, currency, created_at, description) VALUES
    ('b1111111-1111-1111-1111-111111111111', 'buy',  -5000.0000, 'USD', '2025-07-15 10:00', 'P6 demo data'),
    ('b1111111-1111-1111-1111-111111111111', 'sell',  5800.0000, 'USD', '2025-07-20 10:00', 'P6 demo data'),
    ('b1111111-1111-1111-1111-111111111111', 'fee',      -5.0000, 'USD', '2025-07-20 10:00', 'P6 demo data'),

    ('b1111111-1111-1111-1111-111111111111', 'buy',  -4000.0000, 'USD', '2025-10-15 10:00', 'P6 demo data'),
    ('b1111111-1111-1111-1111-111111111111', 'sell',  3500.0000, 'USD', '2025-10-20 10:00', 'P6 demo data'),
    ('b1111111-1111-1111-1111-111111111111', 'fee',      -5.0000, 'USD', '2025-10-20 10:00', 'P6 demo data'),

    ('b1111111-1111-1111-1111-111111111111', 'buy',  -6000.0000, 'USD', '2026-01-15 10:00', 'P6 demo data'),
    ('b1111111-1111-1111-1111-111111111111', 'sell',  6700.0000, 'USD', '2026-01-20 10:00', 'P6 demo data'),
    ('b1111111-1111-1111-1111-111111111111', 'fee',      -5.0000, 'USD', '2026-01-20 10:00', 'P6 demo data'),

    ('b1111111-1111-1111-1111-111111111111', 'buy',  -3000.0000, 'USD', '2026-04-15 10:00', 'P6 demo data'),
    ('b1111111-1111-1111-1111-111111111111', 'sell',  2600.0000, 'USD', '2026-04-20 10:00', 'P6 demo data'),
    ('b1111111-1111-1111-1111-111111111111', 'fee',      -5.0000, 'USD', '2026-04-20 10:00', 'P6 demo data'),

    ('b1111111-1111-1111-1111-111111111111', 'buy',  -4500.0000, 'USD', '2026-07-15 10:00', 'P6 demo data'),
    ('b1111111-1111-1111-1111-111111111111', 'sell',  5200.0000, 'USD', '2026-07-20 10:00', 'P6 demo data'),
    ('b1111111-1111-1111-1111-111111111111', 'fee',      -5.0000, 'USD', '2026-07-20 10:00', 'P6 demo data');

-- ============================================================================
-- Bob: three quarterly round trips, all profitable (100% consistency),
-- smaller total P/L than Alice but a higher ROI.
-- ============================================================================
INSERT INTO transactions (user_id, type, amount, currency, created_at, description) VALUES
    ('b2222222-2222-2222-2222-222222222222', 'buy',  -2000.0000, 'USD', '2025-10-10 10:00', 'P6 demo data'),
    ('b2222222-2222-2222-2222-222222222222', 'sell',  2300.0000, 'USD', '2025-10-12 10:00', 'P6 demo data'),
    ('b2222222-2222-2222-2222-222222222222', 'fee',      -3.0000, 'USD', '2025-10-12 10:00', 'P6 demo data'),

    ('b2222222-2222-2222-2222-222222222222', 'buy',  -2500.0000, 'USD', '2026-01-10 10:00', 'P6 demo data'),
    ('b2222222-2222-2222-2222-222222222222', 'sell',  2900.0000, 'USD', '2026-01-12 10:00', 'P6 demo data'),
    ('b2222222-2222-2222-2222-222222222222', 'fee',      -3.0000, 'USD', '2026-01-12 10:00', 'P6 demo data'),

    ('b2222222-2222-2222-2222-222222222222', 'buy',  -1800.0000, 'USD', '2026-04-10 10:00', 'P6 demo data'),
    ('b2222222-2222-2222-2222-222222222222', 'sell',  2100.0000, 'USD', '2026-04-12 10:00', 'P6 demo data'),
    ('b2222222-2222-2222-2222-222222222222', 'fee',      -3.0000, 'USD', '2026-04-12 10:00', 'P6 demo data');

-- ============================================================================
-- Market trades: BTC/USD trending up, ETH/USD trending down, five quarters.
-- source='p6_demo' keeps these separate from data_load.sql's own rows and
-- from live user/bot fills so this script can clean up after itself.
-- ============================================================================
INSERT INTO market_trades (market_id, executed_at, price, quantity, side, source) VALUES
    ('a1111111-1111-1111-1111-111111111111', '2025-07-15 10:00', 40000.000000, 0.500000, 'buy',  'p6_demo'),
    ('a1111111-1111-1111-1111-111111111111', '2025-10-15 10:00', 45000.000000, 0.800000, 'buy',  'p6_demo'),
    ('a1111111-1111-1111-1111-111111111111', '2026-01-15 10:00', 55000.000000, 1.200000, 'buy',  'p6_demo'),
    ('a1111111-1111-1111-1111-111111111111', '2026-04-15 10:00', 60000.000000, 1.000000, 'buy',  'p6_demo'),

    ('a2222222-2222-2222-2222-222222222222', '2025-07-15 10:00',  4000.000000, 3.000000, 'sell', 'p6_demo'),
    ('a2222222-2222-2222-2222-222222222222', '2025-10-15 10:00',  3800.000000, 2.500000, 'sell', 'p6_demo'),
    ('a2222222-2222-2222-2222-222222222222', '2026-01-15 10:00',  3600.000000, 2.000000, 'sell', 'p6_demo'),
    ('a2222222-2222-2222-2222-222222222222', '2026-04-15 10:00',  3550.000000, 1.800000, 'sell', 'p6_demo');

-- ============================================================================
-- Executed orders: who participated in which market, across the same quarters.
-- ============================================================================
INSERT INTO orders (id, user_id, market_id, side, type, status, quantity, filled_quantity, price, placed_at, executed_at) VALUES
    ('e1111111-1111-1111-1111-111111111111', 'b1111111-1111-1111-1111-111111111111',
     'a1111111-1111-1111-1111-111111111111', 'buy', 'market', 'executed', 0.5000, 0.5000, 40000.000000,
     '2025-07-15 10:00', '2025-07-15 10:00'),
    ('e2222222-2222-2222-2222-222222222222', 'b1111111-1111-1111-1111-111111111111',
     'a2222222-2222-2222-2222-222222222222', 'sell', 'market', 'executed', 3.0000, 3.0000, 4000.000000,
     '2025-10-15 10:00', '2025-10-15 10:00'),
    ('e3333333-3333-3333-3333-333333333333', 'b2222222-2222-2222-2222-222222222222',
     'a1111111-1111-1111-1111-111111111111', 'buy', 'market', 'executed', 1.2000, 1.2000, 55000.000000,
     '2026-01-15 10:00', '2026-01-15 10:00'),
    ('e4444444-4444-4444-4444-444444444444', 'b2222222-2222-2222-2222-222222222222',
     'a1111111-1111-1111-1111-111111111111', 'buy', 'market', 'executed', 1.0000, 1.0000, 60000.000000,
     '2026-04-15 10:00', '2026-04-15 10:00'),
    ('e5555555-5555-5555-5555-555555555555', 'b3333333-3333-3333-3333-333333333333',
     'a2222222-2222-2222-2222-222222222222', 'sell', 'market', 'executed', 2.0000, 2.0000, 3600.000000,
     '2026-01-15 10:00', '2026-01-15 10:00');

UPDATE users u
   SET available_balance = u.available_balance + d.total
  FROM (SELECT user_id, SUM(amount) AS total FROM transactions
         WHERE description = 'P6 demo data' GROUP BY user_id) d
 WHERE u.id = d.user_id;

COMMIT;
