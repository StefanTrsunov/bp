-- advanced_db_tests.sql
-- EduBerza - tests for the P7 rules in advanced_db.sql
--
-- Run right after data_load.sql (seed state: alice 8250 USD + 0.5 ETH,
-- bob 5000 USD, charlie 2500 USD, ETH/USD last traded at 3520).
-- It plays a short trading story and, along the way, tries to break every
-- rule. Each check prints PASS/FAIL as a NOTICE; everything is rolled back
-- at the end, so the data is left exactly as it was.
--
-- The reservation and balance checks are deferred to COMMIT; the tests force
-- them with SET CONSTRAINTS ALL IMMEDIATE so a violation shows up inside the
-- test instead of at the final COMMIT.

BEGIN;
SET search_path TO project, public;

CREATE TEMP TABLE test_results (name text, passed boolean) ON COMMIT DROP;
CREATE TEMP TABLE ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;

-- expect_error: run p_sql (and the deferred checks); it must fail with an
-- error containing p_fragment.
CREATE PROCEDURE pg_temp.expect_error(p_name text, p_sql text, p_fragment text)
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        SET CONSTRAINTS ALL IMMEDIATE;
        RAISE NOTICE 'FAIL  %: no error raised', p_name;
        INSERT INTO test_results VALUES (p_name, false);
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM ILIKE '%' || p_fragment || '%' THEN
            RAISE NOTICE 'PASS  %: %', p_name, SQLERRM;
            INSERT INTO test_results VALUES (p_name, true);
        ELSE
            RAISE NOTICE 'FAIL  %: unexpected error: %', p_name, SQLERRM;
            INSERT INTO test_results VALUES (p_name, false);
        END IF;
    END;
    SET CONSTRAINTS ALL DEFERRED;
END $$;

CREATE FUNCTION pg_temp.expect_true(p_name text, p_ok boolean, p_detail text DEFAULT '')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE '%  %: %', CASE WHEN coalesce(p_ok, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail;
    INSERT INTO test_results VALUES (p_name, coalesce(p_ok, false));
END $$;

-- consistent: all deferred checks pass right now
CREATE FUNCTION pg_temp.consistent() RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
    SET CONSTRAINTS ALL IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;
    RETURN true;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '      consistency check failed: %', SQLERRM;
    RETURN false;
END $$;

CREATE FUNCTION pg_temp.uid(p_name text) RETURNS uuid LANGUAGE sql AS $$
    SELECT id FROM users WHERE username = p_name
$$;
CREATE FUNCTION pg_temp.oid(p_name text) RETURNS uuid LANGUAGE sql AS $$
    SELECT id FROM ids WHERE name = p_name
$$;


-- ===========================================================================
-- A. Placing orders reserves what they commit
-- ===========================================================================
INSERT INTO ids VALUES ('alice_ask',
    place_order(pg_temp.uid('alice'), 'a2222222-2222-2222-2222-222222222222', 'sell', 'limit', 0.3, 3600));
INSERT INTO ids VALUES ('bob_bid',
    place_order(pg_temp.uid('bob'), 'a2222222-2222-2222-2222-222222222222', 'buy', 'limit', 0.1, 3500));

SELECT pg_temp.expect_true('place: limit sell above the market rests in the book, crypto reserved',
    (SELECT status FROM orders WHERE id = pg_temp.oid('alice_ask')) = 'open'
    AND (SELECT reserved_quantity FROM holdings WHERE user_id = pg_temp.uid('alice')) = 0.3,
    'alice ETH reserved = ' || (SELECT reserved_quantity FROM holdings WHERE user_id = pg_temp.uid('alice')));
SELECT pg_temp.expect_true('place: limit buy below the market rests in the book, cash reserved',
    (SELECT (available_balance, reserved_balance) FROM users WHERE username = 'bob') = (4650.0000, 350.0000),
    (SELECT format('bob available %s reserved %s', available_balance, reserved_balance) FROM users WHERE username = 'bob'));
SELECT pg_temp.expect_true('event: placement recorded automatically',
    (SELECT count(*) FROM order_events WHERE order_id IN (pg_temp.oid('alice_ask'), pg_temp.oid('bob_bid'))
      AND event_type = 'placed') = 2);
SELECT pg_temp.expect_true('view: order book shows both price levels',
    (SELECT string_agg(side || ' ' || quantity || ' @ ' || price, ', ' ORDER BY side)
       FROM v_order_book WHERE symbol = 'ETH') = 'buy 0.1000 @ 3500.000000, sell 0.3000 @ 3600.000000',
    (SELECT string_agg(side || ' ' || quantity || ' @ ' || price, ', ' ORDER BY side) FROM v_order_book WHERE symbol = 'ETH'));
SELECT pg_temp.expect_true('consistency holds after placing', pg_temp.consistent());

CALL pg_temp.expect_error('place: buy without enough free cash',
    $q$SELECT place_order(pg_temp.uid('charlie'), 'a1111111-1111-1111-1111-111111111111', 'buy', 'limit', 1, 60000)$q$,
    'insufficient funds');
CALL pg_temp.expect_error('place: sell more than is free (0.2 of 0.5 is already reserved)',
    $q$SELECT place_order(pg_temp.uid('alice'), 'a2222222-2222-2222-2222-222222222222', 'sell', 'limit', 0.3, 3600)$q$,
    'insufficient holding');

-- ===========================================================================
-- B. A trade between two compatible orders, partial fill
-- ===========================================================================
-- bob bids 0.2 at 3650: crosses alice's ask at 3600 -> trade 0.2 @ 3600
INSERT INTO ids VALUES ('bob_bid2',
    place_order(pg_temp.uid('bob'), 'a2222222-2222-2222-2222-222222222222', 'buy', 'limit', 0.2, 3650));

SELECT pg_temp.expect_true('match: trade between the two orders at the resting price',
    EXISTS (SELECT 1 FROM market_trades
             WHERE buy_order_id = pg_temp.oid('bob_bid2') AND sell_order_id = pg_temp.oid('alice_ask')
               AND quantity = 0.2 AND price = 3600 AND source = 'match'));
SELECT pg_temp.expect_true('status: seller partially filled, buyer executed (automatic)',
    (SELECT status || ' ' || filled_quantity FROM orders WHERE id = pg_temp.oid('alice_ask')) = 'partially_filled 0.2000'
    AND (SELECT status FROM orders WHERE id = pg_temp.oid('bob_bid2')) = 'executed',
    (SELECT format('alice_ask %s %s/%s', status, filled_quantity, quantity) FROM orders WHERE id = pg_temp.oid('alice_ask')));
SELECT pg_temp.expect_true('money: buyer paid 720, got back the 10 reserved above the trade price',
    (SELECT (available_balance, reserved_balance) FROM users WHERE username = 'bob') = (3930.0000, 350.0000),
    (SELECT format('bob available %s reserved %s', available_balance, reserved_balance) FROM users WHERE username = 'bob'));
SELECT pg_temp.expect_true('crypto: 0.2 ETH moved from alice (0.1 still reserved) to bob',
    (SELECT (quantity, reserved_quantity) FROM holdings WHERE user_id = pg_temp.uid('alice')) = (0.3000, 0.1000)
    AND (SELECT (quantity, avg_price) FROM holdings WHERE user_id = pg_temp.uid('bob')) = (0.2000, 3600.000000));
SELECT pg_temp.expect_true('ledger: one buy and one sell row, linked to the orders',
    (SELECT count(*) FROM transactions WHERE related_order IN (pg_temp.oid('bob_bid2'), pg_temp.oid('alice_ask'))) = 2);
SELECT pg_temp.expect_true('event: fills recorded automatically',
    (SELECT string_agg(event_type, ',' ORDER BY id) FROM order_events WHERE order_id = pg_temp.oid('alice_ask'))
        = 'placed,partially_filled');
SELECT pg_temp.expect_true('consistency holds after the trade', pg_temp.consistent());

-- ===========================================================================
-- C. Market order: book first, then the simulated market
-- ===========================================================================
-- market price is now 3600 (last trade); charlie buys 0.15 at market:
-- 0.1 from alice's remaining ask @ 3600, the other 0.05 from the market @ 3600
INSERT INTO ids VALUES ('charlie_mkt',
    place_order(pg_temp.uid('charlie'), 'a2222222-2222-2222-2222-222222222222', 'buy', 'market', 0.15));

SELECT pg_temp.expect_true('market order: filled completely in two trades',
    (SELECT (status, trades, avg_fill_price) FROM v_order_history WHERE order_id = pg_temp.oid('charlie_mkt'))
        = ('executed'::varchar, 2::bigint, 3600.000000::numeric),
    (SELECT format('%s, %s trades, avg %s', status, trades, avg_fill_price) FROM v_order_history WHERE order_id = pg_temp.oid('charlie_mkt')));
SELECT pg_temp.expect_true('market order: alice''s ask is now executed, nothing left reserved',
    (SELECT status FROM orders WHERE id = pg_temp.oid('alice_ask')) = 'executed'
    AND (SELECT reserved_quantity FROM holdings WHERE user_id = pg_temp.uid('alice')) = 0
    AND (SELECT reserved_balance FROM users WHERE username = 'charlie') = 0);
SELECT pg_temp.expect_true('consistency holds after the market order', pg_temp.consistent());

-- ===========================================================================
-- D. Trades are only possible between valid, compatible orders
-- ===========================================================================
INSERT INTO ids VALUES ('charlie_ask',
    place_order(pg_temp.uid('charlie'), 'a2222222-2222-2222-2222-222222222222', 'sell', 'limit', 0.1, 3700));
INSERT INTO ids VALUES ('bob_ask',
    place_order(pg_temp.uid('bob'), 'a2222222-2222-2222-2222-222222222222', 'sell', 'limit', 0.1, 3800));

CALL pg_temp.expect_error('trade: price above the buyer''s limit',
    $q$INSERT INTO market_trades (market_id, executed_at, price, quantity, buy_order_id, sell_order_id)
       VALUES ('a2222222-2222-2222-2222-222222222222', now(), 3700, 0.1, pg_temp.oid('bob_bid'), pg_temp.oid('charlie_ask'))$q$,
    'outside the limit');
CALL pg_temp.expect_error('trade: more than the order has remaining',
    $q$INSERT INTO market_trades (market_id, executed_at, price, quantity, buy_order_id)
       VALUES ('a2222222-2222-2222-2222-222222222222', now(), 3500, 0.5, pg_temp.oid('bob_bid'))$q$,
    'exceeds the remaining quantity');
CALL pg_temp.expect_error('trade: a sell order used as the buy side',
    $q$INSERT INTO market_trades (market_id, executed_at, price, quantity, buy_order_id)
       VALUES ('a2222222-2222-2222-2222-222222222222', now(), 3700, 0.1, pg_temp.oid('charlie_ask'))$q$,
    'cannot be the buy side');
CALL pg_temp.expect_error('trade: order of another market',
    $q$INSERT INTO market_trades (market_id, executed_at, price, quantity, buy_order_id)
       VALUES ('a1111111-1111-1111-1111-111111111111', now(), 3500, 0.1, pg_temp.oid('bob_bid'))$q$,
    'different market');
CALL pg_temp.expect_error('trade: executed order cannot trade again',
    $q$INSERT INTO market_trades (market_id, executed_at, price, quantity, sell_order_id)
       VALUES ('a2222222-2222-2222-2222-222222222222', now(), 3600, 0.1, pg_temp.oid('alice_ask'))$q$,
    'is executed and cannot trade');
CALL pg_temp.expect_error('trade: a user with their own order',
    $q$INSERT INTO market_trades (market_id, executed_at, price, quantity, buy_order_id, sell_order_id)
       VALUES ('a2222222-2222-2222-2222-222222222222', now(), 3500, 0.1, pg_temp.oid('bob_bid'), pg_temp.oid('bob_ask'))$q$,
    'own order');
CALL pg_temp.expect_error('trade: a trade that filled orders cannot be deleted',
    $q$DELETE FROM market_trades WHERE buy_order_id = pg_temp.oid('bob_bid2')$q$,
    'cannot be changed or deleted');

-- ===========================================================================
-- E. Order state changes
-- ===========================================================================
CALL pg_temp.expect_error('state: status cannot be set to executed by hand',
    $q$UPDATE orders SET status = 'executed' WHERE id = pg_temp.oid('bob_bid')$q$,
    'status is derived automatically');
CALL pg_temp.expect_error('state: filled quantity cannot be changed by hand',
    $q$UPDATE orders SET filled_quantity = 0.05 WHERE id = pg_temp.oid('bob_bid')$q$,
    'can only change through a trade');
CALL pg_temp.expect_error('state: executed order cannot be processed again',
    $q$UPDATE orders SET status = 'cancelled' WHERE id = pg_temp.oid('alice_ask')$q$,
    'already executed');
CALL pg_temp.expect_error('state: ordered quantity cannot change',
    $q$UPDATE orders SET quantity = 1 WHERE id = pg_temp.oid('bob_bid')$q$,
    'cannot change');
CALL pg_temp.expect_error('state: cancelling by hand without releasing the reservation',
    $q$UPDATE orders SET status = 'cancelled' WHERE id = pg_temp.oid('bob_bid')$q$,
    'reserved balance');

-- ===========================================================================
-- F. Cancelling releases the reservation, exactly once
-- ===========================================================================
CALL pg_temp.expect_error('cancel: someone else''s order',
    $q$SELECT cancel_order(pg_temp.oid('bob_bid'), pg_temp.uid('charlie'))$q$,
    'does not belong');
SELECT cancel_order(pg_temp.oid('bob_bid'), pg_temp.uid('bob'));
SELECT pg_temp.expect_true('cancel: 350 back from reserved to available, event recorded',
    (SELECT (available_balance, reserved_balance) FROM users WHERE username = 'bob') = (4280.0000, 0.0000)
    AND EXISTS (SELECT 1 FROM order_events WHERE order_id = pg_temp.oid('bob_bid') AND event_type = 'cancelled'),
    (SELECT format('bob available %s reserved %s', available_balance, reserved_balance) FROM users WHERE username = 'bob'));
CALL pg_temp.expect_error('cancel: a cancelled order cannot be cancelled again',
    $q$SELECT cancel_order(pg_temp.oid('bob_bid'), pg_temp.uid('bob'))$q$,
    'cannot be cancelled');
CALL pg_temp.expect_error('trade: cancelled order cannot trade',
    $q$INSERT INTO market_trades (market_id, executed_at, price, quantity, buy_order_id)
       VALUES ('a2222222-2222-2222-2222-222222222222', now(), 3500, 0.1, pg_temp.oid('bob_bid'))$q$,
    'is cancelled and cannot trade');

-- ===========================================================================
-- G. Balances cannot be put in an inconsistent state
-- ===========================================================================
CALL pg_temp.expect_error('balance: reserving cash with no order behind it',
    $q$UPDATE users SET available_balance = available_balance - 100, reserved_balance = reserved_balance + 100
        WHERE username = 'charlie'$q$,
    'reserved balance');
CALL pg_temp.expect_error('balance: reserving crypto with no order behind it',
    $q$UPDATE holdings SET reserved_quantity = reserved_quantity + 0.01 WHERE user_id = pg_temp.uid('alice')$q$,
    'reserved quantity');
CALL pg_temp.expect_error('balance: cash changed without a ledger row',
    $q$UPDATE users SET available_balance = available_balance + 100 WHERE username = 'charlie'$q$,
    'does not match the ledger');

-- ===========================================================================
-- H. Background job: resting limit orders filled when the market reaches them
-- ===========================================================================
INSERT INTO ids VALUES ('bob_bid3',
    place_order(pg_temp.uid('bob'), 'a2222222-2222-2222-2222-222222222222', 'buy', 'limit', 0.1, 3500));
-- the simulator moves the price down to 3450 (a bot tick, no orders)
INSERT INTO market_trades (market_id, executed_at, price, quantity, side)
VALUES ('a2222222-2222-2222-2222-222222222222', now(), 3450, 0.01, 'sell');

CREATE TEMP TABLE job_run ON COMMIT DROP AS SELECT fill_marketable_orders() AS filled;

SELECT pg_temp.expect_true('job: fills exactly the orders the new price reached',
    (SELECT filled FROM job_run) = 1
    AND (SELECT (status, avg_fill_price) FROM v_order_history WHERE order_id = pg_temp.oid('bob_bid3'))
        = ('executed'::varchar, 3450.000000::numeric)
    AND (SELECT status FROM orders WHERE id = pg_temp.oid('charlie_ask')) = 'open',
    (SELECT format('bob_bid3 %s @ %s, charlie_ask (3700) still %s', h.status, h.avg_fill_price, o.status)
       FROM v_order_history h, orders o WHERE h.order_id = pg_temp.oid('bob_bid3') AND o.id = pg_temp.oid('charlie_ask')));
SELECT pg_temp.expect_true('job: buyer paid 345, got the 5 above the fill price back',
    (SELECT reserved_balance FROM users WHERE username = 'bob') = 0
    AND (SELECT count(*) FROM transactions WHERE related_order = pg_temp.oid('bob_bid3') AND amount = -345) = 1);
SELECT pg_temp.expect_true('job: nothing more to do on a second run', fill_marketable_orders() = 0);
SELECT pg_temp.expect_true('consistency holds after the job', pg_temp.consistent());

-- ===========================================================================
-- Final state of every trader
-- ===========================================================================
SELECT pg_temp.expect_true('views: every trader''s cash equals their ledger',
    NOT EXISTS (SELECT 1 FROM v_trader_balances WHERE total_cash <> ledger_total));

SELECT username, available_balance, reserved_balance, ledger_total, holdings_value
  FROM v_trader_balances ORDER BY username;

SELECT count(*) FILTER (WHERE passed)     AS passed,
       count(*) FILTER (WHERE NOT passed) AS failed
  FROM test_results;

ROLLBACK;
