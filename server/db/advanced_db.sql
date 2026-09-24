-- advanced_db.sql
-- EduBerza - P7 Advanced Database Development
-- Course: Databases 2025/2026 Winter, FINKI UKIM
--
-- Order, reservation and trade consistency implemented in the database.
-- Run after schema_creation.sql and before data_load.sql (-init does both).
--
--   1. Order lifecycle      - status is derived from filled_quantity, only
--                             valid transitions, finished orders are final,
--                             filled_quantity only changes through a trade.
--   2. Trade consistency    - a trade row may only fill compatible, active
--                             orders, never more than they have remaining;
--                             inserting it fills the orders automatically.
--   3. Reservations/balance - reserved cash and reserved crypto always equal
--                             what the user's active orders still need, and
--                             cash (available + reserved) always equals the
--                             ledger. Checked at COMMIT.
--   4. Order events         - every placement, fill and cancellation is
--                             recorded automatically.
--   5. Operations           - place_order, execute_trade, cancel_order.
--   6. Views                - order book, active orders, order history,
--                             trader balances.
--   7. Background job       - fills resting limit orders once the simulated
--                             market price reaches them.

SET search_path TO project, public;

-- Cash a buy order still holds in reserve: its remaining quantity at its
-- price, rounded to the 4 decimals of the balance columns. Defined once so
-- placing, filling, cancelling and checking all round the same way.
CREATE OR REPLACE FUNCTION project.order_reservation(p_remaining numeric, p_price numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT round(p_remaining * p_price, 4)
$$;

-- Latest traded price of a market (the simulated market price).
CREATE OR REPLACE FUNCTION project.latest_price(p_market_id uuid)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT price FROM project.market_trades
     WHERE market_id = p_market_id
     ORDER BY executed_at DESC, id DESC
     LIMIT 1
$$;

-- ============================================================================
-- 1. ORDER LIFECYCLE
-- ============================================================================

-- Automatic recording of order events (placement, fills, cancellation).
CREATE TABLE project.order_events (
    id           bigserial      PRIMARY KEY,
    order_id     uuid           NOT NULL REFERENCES project.orders(id) ON DELETE CASCADE,
    event_type   varchar(20)    NOT NULL
                 CHECK (event_type IN ('placed', 'partially_filled', 'filled', 'cancelled')),
    quantity     numeric(20,4)  NOT NULL,
    price        numeric(18,6),
    status_after varchar(20)    NOT NULL,
    created_at   timestamptz    NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX idx_order_events_order ON project.order_events(order_id, id);

-- Status is not set by hand: it follows from how much has been filled.
--   filled = 0          -> open
--   0 < filled < qty    -> partially_filled
--   filled = qty        -> executed (executed_at set)
-- The only status that is set explicitly is 'cancelled', and only on an
-- active order. executed and cancelled orders are final. What was ordered
-- never changes. filled_quantity only changes when a trade fills the order
-- (the trade trigger sets a transaction-local flag while it does that).
CREATE OR REPLACE FUNCTION project.trg_orders_lifecycle()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_derived varchar(20);
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.status IN ('executed', 'cancelled') THEN
            RAISE EXCEPTION 'order % is already % and cannot be processed again', OLD.id, OLD.status
                USING ERRCODE = 'check_violation';
        END IF;
        IF (NEW.user_id, NEW.market_id, NEW.side, NEW.type, NEW.quantity, NEW.price, NEW.placed_at)
           IS DISTINCT FROM
           (OLD.user_id, OLD.market_id, OLD.side, OLD.type, OLD.quantity, OLD.price, OLD.placed_at) THEN
            RAISE EXCEPTION 'user, market, side, type, quantity, price and placed_at of an order cannot change'
                USING ERRCODE = 'check_violation';
        END IF;
        IF NEW.filled_quantity <> OLD.filled_quantity THEN
            IF current_setting('eduberza.trade_fill', true) IS DISTINCT FROM 'on' THEN
                RAISE EXCEPTION 'filled quantity of order % can only change through a trade', OLD.id
                    USING ERRCODE = 'check_violation';
            END IF;
            IF NEW.filled_quantity < OLD.filled_quantity THEN
                RAISE EXCEPTION 'filled quantity of order % cannot decrease', OLD.id
                    USING ERRCODE = 'check_violation';
            END IF;
        END IF;
        IF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' THEN
            IF NEW.filled_quantity <> OLD.filled_quantity THEN
                RAISE EXCEPTION 'an order cannot be filled and cancelled in the same step'
                    USING ERRCODE = 'check_violation';
            END IF;
            NEW.executed_at := NULL;
            RETURN NEW;
        END IF;
    ELSE
        IF NOT EXISTS (SELECT 1 FROM project.markets WHERE id = NEW.market_id AND is_active) THEN
            RAISE EXCEPTION 'market % is not active; no new orders accepted', NEW.market_id
                USING ERRCODE = 'check_violation';
        END IF;
        IF NEW.price IS NULL OR NEW.price <= 0 THEN
            RAISE EXCEPTION 'an order needs a positive price (limit price, or the market price for a market order)'
                USING ERRCODE = 'check_violation';
        END IF;
        IF NEW.status = 'cancelled' THEN
            RAISE EXCEPTION 'an order cannot be created already cancelled'
                USING ERRCODE = 'check_violation';
        END IF;
        -- A new order starts unfilled. The only exception is importing an
        -- order that was completely executed in the past (sample data).
        IF NEW.filled_quantity NOT IN (0, NEW.quantity) THEN
            RAISE EXCEPTION 'a new order is either unfilled or (imported history) completely filled'
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    v_derived := CASE
        WHEN NEW.filled_quantity = 0               THEN 'open'
        WHEN NEW.filled_quantity < NEW.quantity    THEN 'partially_filled'
        ELSE 'executed'
    END;
    IF NEW.status IS DISTINCT FROM v_derived
       AND (TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status) THEN
        RAISE EXCEPTION 'order status % does not match filled quantity % of %; status is derived automatically',
            NEW.status, NEW.filled_quantity, NEW.quantity
            USING ERRCODE = 'check_violation';
    END IF;
    NEW.status := v_derived;

    IF v_derived = 'executed' THEN
        NEW.executed_at := COALESCE(NEW.executed_at, now());
    ELSE
        NEW.executed_at := NULL;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER orders_lifecycle
    BEFORE INSERT OR UPDATE ON project.orders
    FOR EACH ROW EXECUTE FUNCTION project.trg_orders_lifecycle();

CREATE OR REPLACE FUNCTION project.trg_orders_events()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO project.order_events (order_id, event_type, quantity, price, status_after)
        VALUES (NEW.id, 'placed', NEW.quantity, NEW.price, NEW.status);
    ELSIF NEW.filled_quantity > OLD.filled_quantity THEN
        INSERT INTO project.order_events (order_id, event_type, quantity, price, status_after)
        VALUES (NEW.id,
                CASE WHEN NEW.status = 'executed' THEN 'filled' ELSE 'partially_filled' END,
                NEW.filled_quantity - OLD.filled_quantity,
                current_setting('eduberza.trade_price', true)::numeric,
                NEW.status);
    ELSIF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' THEN
        INSERT INTO project.order_events (order_id, event_type, quantity, price, status_after)
        VALUES (NEW.id, 'cancelled', NEW.quantity - NEW.filled_quantity, NEW.price, NEW.status);
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER orders_events
    AFTER INSERT OR UPDATE ON project.orders
    FOR EACH ROW EXECUTE FUNCTION project.trg_orders_events();

-- ============================================================================
-- 2. TRADE CONSISTENCY
-- ============================================================================

-- A trade that names orders must be possible for those orders:
--   * the buy_order_id is a buy order and the sell_order_id a sell order,
--   * both are on the trade's market and still active (open or partially
--     filled) - a cancelled or executed order can never trade again,
--   * the trade quantity does not exceed either order's remaining quantity,
--   * the price respects both limits (buy: price <= its limit, sell:
--     price >= its limit),
--   * the two orders belong to different users (no self-trade).
-- A trade with no orders at all is a simulated market tick (the bot).
CREATE OR REPLACE FUNCTION project.trg_market_trades_validate()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    o     project.orders%ROWTYPE;
    v_uid uuid;
    v_id  uuid;
    v_role varchar(4);
BEGIN
    IF NEW.buy_order_id IS NULL AND NEW.sell_order_id IS NULL THEN
        RETURN NEW;
    END IF;
    IF NEW.buy_order_id IS NOT DISTINCT FROM NEW.sell_order_id THEN
        RAISE EXCEPTION 'an order cannot trade with itself'
            USING ERRCODE = 'check_violation';
    END IF;

    FOREACH v_role IN ARRAY ARRAY['buy', 'sell'] LOOP
        v_id := CASE v_role WHEN 'buy' THEN NEW.buy_order_id ELSE NEW.sell_order_id END;
        CONTINUE WHEN v_id IS NULL;

        SELECT * INTO o FROM project.orders WHERE id = v_id FOR UPDATE;
        IF o.side <> v_role THEN
            RAISE EXCEPTION 'order % is a % order and cannot be the % side of a trade', v_id, o.side, v_role
                USING ERRCODE = 'check_violation';
        END IF;
        IF o.market_id <> NEW.market_id THEN
            RAISE EXCEPTION 'order % is on a different market than the trade', v_id
                USING ERRCODE = 'check_violation';
        END IF;
        IF o.status NOT IN ('open', 'partially_filled') THEN
            RAISE EXCEPTION 'order % is % and cannot trade', v_id, o.status
                USING ERRCODE = 'check_violation';
        END IF;
        IF NEW.quantity > o.quantity - o.filled_quantity THEN
            RAISE EXCEPTION 'trade quantity % exceeds the remaining quantity % of order %',
                NEW.quantity, o.quantity - o.filled_quantity, v_id
                USING ERRCODE = 'check_violation';
        END IF;
        IF v_uid IS NOT NULL AND v_uid = o.user_id THEN
            RAISE EXCEPTION 'a user cannot trade with their own order'
                USING ERRCODE = 'check_violation';
        END IF;
        IF v_role = 'buy' AND NEW.price > o.price OR v_role = 'sell' AND NEW.price < o.price THEN
            RAISE EXCEPTION 'trade price % is outside the limit % of % order %', NEW.price, o.price, v_role, v_id
                USING ERRCODE = 'check_violation';
        END IF;
        v_uid := o.user_id;
    END LOOP;
    RETURN NEW;
END $$;

CREATE TRIGGER market_trades_validate
    BEFORE INSERT ON project.market_trades
    FOR EACH ROW EXECUTE FUNCTION project.trg_market_trades_validate();

-- Recording a trade fills the orders it names; their status follows via
-- orders_lifecycle. The flag is what orders_lifecycle checks to allow the
-- change of filled_quantity.
CREATE OR REPLACE FUNCTION project.trg_market_trades_fill()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.buy_order_id IS NULL AND NEW.sell_order_id IS NULL THEN
        RETURN NULL;
    END IF;
    PERFORM set_config('eduberza.trade_fill', 'on', true);
    PERFORM set_config('eduberza.trade_price', NEW.price::text, true);
    UPDATE project.orders
       SET filled_quantity = filled_quantity + NEW.quantity,
           executed_at     = CASE WHEN filled_quantity + NEW.quantity = quantity
                                  THEN NEW.executed_at END
     WHERE id IN (NEW.buy_order_id, NEW.sell_order_id);
    PERFORM set_config('eduberza.trade_fill', 'off', true);
    RETURN NULL;
END $$;

CREATE TRIGGER market_trades_fill
    AFTER INSERT ON project.market_trades
    FOR EACH ROW EXECUTE FUNCTION project.trg_market_trades_fill();

-- Trades are history: they are never changed or removed (the fills and the
-- money they moved would no longer match).
CREATE OR REPLACE FUNCTION project.trg_market_trades_immutable()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.buy_order_id IS NULL AND OLD.sell_order_id IS NULL THEN
        -- a simulated tick filled no order; allow it unless it is being
        -- turned into one that did
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        ELSIF NEW.buy_order_id IS NULL AND NEW.sell_order_id IS NULL THEN
            RETURN NEW;
        END IF;
    END IF;
    RAISE EXCEPTION 'a trade that filled orders cannot be changed or deleted'
        USING ERRCODE = 'check_violation';
END $$;

CREATE TRIGGER market_trades_immutable
    BEFORE UPDATE OR DELETE ON project.market_trades
    FOR EACH ROW EXECUTE FUNCTION project.trg_market_trades_immutable();

-- ============================================================================
-- 3. RESERVATIONS AND BALANCES  (deferred: checked at COMMIT)
-- ============================================================================
-- Placing, filling and cancelling an order each change several rows in
-- separate statements, and in between the rows disagree. Only the state at
-- COMMIT must be consistent, so these are DEFERRABLE INITIALLY DEFERRED
-- constraint triggers: a transaction that leaves any of them broken is
-- rolled back as a whole.

-- 3a. reserved_balance = what the user's active buy orders still reserve.
CREATE OR REPLACE FUNCTION project.trg_reserved_cash_matches_orders()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_user     uuid := CASE WHEN TG_TABLE_NAME = 'users' THEN NEW.id END;
    v_reserved numeric;
    v_needed   numeric;
BEGIN
    IF TG_TABLE_NAME = 'orders' THEN
        v_user := NEW.user_id;
    END IF;
    SELECT reserved_balance INTO v_reserved FROM project.users WHERE id = v_user;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    SELECT COALESCE(SUM(project.order_reservation(quantity - filled_quantity, price)), 0)
      INTO v_needed
      FROM project.orders
     WHERE user_id = v_user AND side = 'buy' AND status IN ('open', 'partially_filled');
    IF v_reserved <> v_needed THEN
        RAISE EXCEPTION 'reserved balance % does not match the % needed by active buy orders (user %)',
            v_reserved, v_needed, v_user
            USING ERRCODE = 'check_violation', CONSTRAINT = 'reserved_cash_matches_orders';
    END IF;
    RETURN NULL;
END $$;

-- 3b. holdings.reserved_quantity = what the user's active sell orders for
--     that crypto still have to deliver.
CREATE OR REPLACE FUNCTION project.trg_reserved_crypto_matches_orders()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_user     uuid;
    v_crypto   uuid;
    v_reserved numeric;
    v_needed   numeric;
BEGIN
    IF TG_TABLE_NAME = 'holdings' THEN
        v_user := NEW.user_id;
        v_crypto := NEW.crypto_id;
    ELSE
        IF NEW.side <> 'sell' THEN
            RETURN NULL;
        END IF;
        v_user := NEW.user_id;
        SELECT crypto_id INTO v_crypto FROM project.markets WHERE id = NEW.market_id;
    END IF;
    SELECT COALESCE(SUM(reserved_quantity), 0) INTO v_reserved
      FROM project.holdings WHERE user_id = v_user AND crypto_id = v_crypto;
    SELECT COALESCE(SUM(o.quantity - o.filled_quantity), 0) INTO v_needed
      FROM project.orders o
      JOIN project.markets m ON m.id = o.market_id
     WHERE o.user_id = v_user AND m.crypto_id = v_crypto
       AND o.side = 'sell' AND o.status IN ('open', 'partially_filled');
    IF v_reserved <> v_needed THEN
        RAISE EXCEPTION 'reserved quantity % does not match the % needed by active sell orders (user %, crypto %)',
            v_reserved, v_needed, v_user, v_crypto
            USING ERRCODE = 'check_violation', CONSTRAINT = 'reserved_crypto_matches_orders';
    END IF;
    RETURN NULL;
END $$;

-- 3c. available_balance + reserved_balance = sum of the user's ledger.
--     Reserving only moves cash between the two columns; money actually
--     leaves or arrives only with a ledger row (deposit, buy fill, sell fill).
CREATE OR REPLACE FUNCTION project.trg_cash_matches_ledger()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_user   uuid;
    v_cash   numeric;
    v_ledger numeric;
BEGIN
    IF TG_TABLE_NAME = 'users' THEN
        v_user := NEW.id;
    ELSIF TG_OP = 'DELETE' THEN
        v_user := OLD.user_id;
    ELSE
        v_user := NEW.user_id;
    END IF;
    SELECT available_balance + reserved_balance INTO v_cash FROM project.users WHERE id = v_user;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    SELECT COALESCE(SUM(amount), 0) INTO v_ledger FROM project.transactions WHERE user_id = v_user;
    IF v_cash <> v_ledger THEN
        RAISE EXCEPTION 'cash % (available + reserved) does not match the ledger total % (user %)',
            v_cash, v_ledger, v_user
            USING ERRCODE = 'check_violation', CONSTRAINT = 'cash_matches_ledger';
    END IF;
    RETURN NULL;
END $$;

CREATE INDEX idx_orders_active ON project.orders (user_id, side)
    WHERE status IN ('open', 'partially_filled');

CREATE CONSTRAINT TRIGGER reserved_cash_matches_orders
    AFTER INSERT OR UPDATE OF reserved_balance ON project.users
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION project.trg_reserved_cash_matches_orders();
CREATE CONSTRAINT TRIGGER reserved_cash_matches_orders
    AFTER INSERT OR UPDATE OF status, filled_quantity ON project.orders
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION project.trg_reserved_cash_matches_orders();

CREATE CONSTRAINT TRIGGER reserved_crypto_matches_orders
    AFTER INSERT OR UPDATE OF reserved_quantity ON project.holdings
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION project.trg_reserved_crypto_matches_orders();
CREATE CONSTRAINT TRIGGER reserved_crypto_matches_orders
    AFTER INSERT OR UPDATE OF status, filled_quantity ON project.orders
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION project.trg_reserved_crypto_matches_orders();

CREATE CONSTRAINT TRIGGER cash_matches_ledger
    AFTER INSERT OR UPDATE OF available_balance, reserved_balance ON project.users
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION project.trg_cash_matches_ledger();
CREATE CONSTRAINT TRIGGER cash_matches_ledger
    AFTER INSERT OR UPDATE OR DELETE ON project.transactions
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION project.trg_cash_matches_ledger();

-- ============================================================================
-- 5. OPERATIONS
-- ============================================================================

-- execute_trade: one trade of p_quantity at p_price between a buy order and
-- a sell order. Either side may be NULL, meaning the simulated market is the
-- counterparty. Inserting the trade row validates it and fills the orders
-- (triggers above); this function moves the money and the crypto:
--   buyer:  reservation released for the filled part, the actual cost paid
--           (any difference to the limit price goes back to available),
--           crypto added to the holding at a running weighted average,
--           'buy' ledger row.
--   seller: reserved crypto delivered out of the holding, proceeds credited,
--           cost basis removed from invested_balance, 'sell' ledger row.
CREATE OR REPLACE FUNCTION project.execute_trade(
    p_buy_order uuid, p_sell_order uuid, p_quantity numeric, p_price numeric,
    p_aggressor varchar DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
    b          project.orders%ROWTYPE;
    s          project.orders%ROWTYPE;
    v_market   project.markets%ROWTYPE;
    v_trade_id bigint;
    v_release  numeric;
    v_cost     numeric;
    v_proceeds numeric;
    v_avg      numeric;
BEGIN
    IF p_buy_order IS NULL AND p_sell_order IS NULL THEN
        RAISE EXCEPTION 'a trade needs at least one order' USING ERRCODE = 'check_violation';
    END IF;

    -- lock both orders in a fixed order (by id) so two concurrent trades on
    -- the same pair of orders cannot deadlock
    PERFORM 1 FROM project.orders WHERE id IN (p_buy_order, p_sell_order) ORDER BY id FOR UPDATE;
    SELECT * INTO b FROM project.orders WHERE id = p_buy_order;
    SELECT * INTO s FROM project.orders WHERE id = p_sell_order;
    SELECT * INTO v_market FROM project.markets WHERE id = COALESCE(b.market_id, s.market_id);

    INSERT INTO project.market_trades
           (market_id, executed_at, price, quantity, side, source, buy_order_id, sell_order_id)
    VALUES (v_market.id, now(), p_price, p_quantity,
            COALESCE(p_aggressor, CASE WHEN p_sell_order IS NULL THEN 'buy' ELSE 'sell' END),
            CASE WHEN p_buy_order IS NOT NULL AND p_sell_order IS NOT NULL THEN 'match' ELSE 'market' END,
            p_buy_order, p_sell_order)
    RETURNING id INTO v_trade_id;

    IF p_buy_order IS NOT NULL THEN
        v_release := project.order_reservation(b.quantity - b.filled_quantity, b.price)
                   - project.order_reservation(b.quantity - b.filled_quantity - p_quantity, b.price);
        v_cost    := LEAST(round(p_quantity * p_price, 4), v_release);

        UPDATE project.users
           SET reserved_balance  = reserved_balance  - v_release,
               available_balance = available_balance + (v_release - v_cost),
               invested_balance  = invested_balance  + v_cost,
               updated_at        = now()
         WHERE id = b.user_id;

        INSERT INTO project.holdings AS h (user_id, crypto_id, quantity, avg_price, updated_at)
        VALUES (b.user_id, v_market.crypto_id, p_quantity, p_price, now())
        ON CONFLICT (user_id, crypto_id) DO UPDATE
           SET avg_price  = (h.quantity * h.avg_price + EXCLUDED.quantity * EXCLUDED.avg_price)
                            / (h.quantity + EXCLUDED.quantity),
               quantity   = h.quantity + EXCLUDED.quantity,
               updated_at = now();

        INSERT INTO project.transactions (user_id, type, amount, currency, related_order, description)
        VALUES (b.user_id, 'buy', -v_cost, v_market.quote_currency, b.id,
                format('Buy %s @ %s (trade %s)', p_quantity, p_price, v_trade_id));
    END IF;

    IF p_sell_order IS NOT NULL THEN
        SELECT avg_price INTO v_avg FROM project.holdings
         WHERE user_id = s.user_id AND crypto_id = v_market.crypto_id FOR UPDATE;

        UPDATE project.holdings
           SET quantity          = quantity - p_quantity,
               reserved_quantity = reserved_quantity - p_quantity,
               updated_at        = now()
         WHERE user_id = s.user_id AND crypto_id = v_market.crypto_id;

        v_proceeds := round(p_quantity * p_price, 4);
        UPDATE project.users
           SET available_balance = available_balance + v_proceeds,
               invested_balance  = GREATEST(invested_balance - round(p_quantity * v_avg, 4), 0),
               updated_at        = now()
         WHERE id = s.user_id;

        INSERT INTO project.transactions (user_id, type, amount, currency, related_order, description)
        VALUES (s.user_id, 'sell', v_proceeds, v_market.quote_currency, s.id,
                format('Sell %s @ %s (trade %s)', p_quantity, p_price, v_trade_id));
    END IF;

    RETURN v_trade_id;
END $$;

-- match_order: trade an order against the opposite side of the order book -
-- other users' active limit orders on the same market whose price is
-- acceptable - best price first, then oldest first (price-time priority).
-- Each trade is at the resting order's price. Returns the number of trades.
CREATE OR REPLACE FUNCTION project.match_order(p_order_id uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
    o       project.orders%ROWTYPE;
    r       record;
    v_rem   numeric;
    v_qty   numeric;
    v_count int := 0;
BEGIN
    SELECT * INTO o FROM project.orders WHERE id = p_order_id FOR UPDATE;
    FOR r IN
        SELECT id, price, quantity - filled_quantity AS remaining
          FROM project.orders
         WHERE market_id = o.market_id
           AND side <> o.side
           AND type = 'limit'
           AND status IN ('open', 'partially_filled')
           AND user_id <> o.user_id
           AND (o.side = 'buy'  AND price <= o.price
             OR o.side = 'sell' AND price >= o.price)
         ORDER BY CASE WHEN o.side = 'buy'  THEN price END ASC,
                  CASE WHEN o.side = 'sell' THEN price END DESC,
                  placed_at, id
           FOR UPDATE
    LOOP
        SELECT quantity - filled_quantity INTO v_rem FROM project.orders WHERE id = p_order_id;
        EXIT WHEN v_rem = 0;
        v_qty := LEAST(v_rem, r.remaining);
        IF o.side = 'buy' THEN
            PERFORM project.execute_trade(o.id, r.id, v_qty, r.price, 'buy');
        ELSE
            PERFORM project.execute_trade(r.id, o.id, v_qty, r.price, 'sell');
        END IF;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END $$;

-- place_order: the one correct way to place an order.
--   1. checks the market, side, type, quantity and price;
--   2. locks the user and reserves what the order commits: cash
--      (remaining x price) for a buy, crypto for a sell - refusing the order
--      if not enough is free;
--   3. records the order (open);
--   4. matches it against the order book (match_order);
--   5. whatever is still unfilled and is marketable at the current market
--      price trades with the simulated market. A market order is priced at
--      the current market price, so it always fills completely here; a limit
--      order that is not marketable stays in the book.
-- Returns the order id.
CREATE OR REPLACE FUNCTION project.place_order(
    p_user_id uuid, p_market_id uuid, p_side varchar, p_type varchar,
    p_quantity numeric, p_limit_price numeric DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
    v_market    numeric := project.latest_price(p_market_id);
    v_price     numeric;
    v_available numeric;
    v_free      numeric;
    v_crypto    uuid;
    v_order     uuid;
    v_rem       numeric;
BEGIN
    IF p_side NOT IN ('buy', 'sell') OR p_type NOT IN ('market', 'limit') THEN
        RAISE EXCEPTION 'invalid side % or type %', p_side, p_type USING ERRCODE = 'check_violation';
    END IF;
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'quantity must be positive' USING ERRCODE = 'check_violation';
    END IF;
    IF p_type = 'limit' THEN
        IF p_limit_price IS NULL OR p_limit_price <= 0 THEN
            RAISE EXCEPTION 'a limit order needs a positive limit price' USING ERRCODE = 'check_violation';
        END IF;
        v_price := p_limit_price;
    ELSE
        IF v_market IS NULL THEN
            RAISE EXCEPTION 'market has no price yet' USING ERRCODE = 'check_violation';
        END IF;
        v_price := v_market;
    END IF;

    SELECT available_balance INTO v_available FROM project.users WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'user % does not exist', p_user_id USING ERRCODE = 'no_data_found';
    END IF;

    IF p_side = 'buy' THEN
        IF v_available < project.order_reservation(p_quantity, v_price) THEN
            RAISE EXCEPTION 'insufficient funds: the order needs %, available %',
                project.order_reservation(p_quantity, v_price), v_available
                USING ERRCODE = 'check_violation';
        END IF;
        UPDATE project.users
           SET available_balance = available_balance - project.order_reservation(p_quantity, v_price),
               reserved_balance  = reserved_balance  + project.order_reservation(p_quantity, v_price),
               updated_at        = now()
         WHERE id = p_user_id;
    ELSE
        SELECT crypto_id INTO v_crypto FROM project.markets WHERE id = p_market_id;
        SELECT quantity - reserved_quantity INTO v_free FROM project.holdings
         WHERE user_id = p_user_id AND crypto_id = v_crypto FOR UPDATE;
        IF COALESCE(v_free, 0) < p_quantity THEN
            RAISE EXCEPTION 'insufficient holding: trying to sell %, free to sell %', p_quantity, COALESCE(v_free, 0)
                USING ERRCODE = 'check_violation';
        END IF;
        UPDATE project.holdings
           SET reserved_quantity = reserved_quantity + p_quantity, updated_at = now()
         WHERE user_id = p_user_id AND crypto_id = v_crypto;
    END IF;

    INSERT INTO project.orders (user_id, market_id, side, type, status, quantity, price)
    VALUES (p_user_id, p_market_id, p_side, p_type, 'open', p_quantity, v_price)
    RETURNING id INTO v_order;

    PERFORM project.match_order(v_order);

    SELECT quantity - filled_quantity INTO v_rem FROM project.orders WHERE id = v_order;
    IF v_rem > 0 AND v_market IS NOT NULL
       AND (p_side = 'buy' AND v_market <= v_price OR p_side = 'sell' AND v_market >= v_price) THEN
        IF p_side = 'buy' THEN
            PERFORM project.execute_trade(v_order, NULL, v_rem, v_market, 'buy');
        ELSE
            PERFORM project.execute_trade(NULL, v_order, v_rem, v_market, 'sell');
        END IF;
    END IF;
    RETURN v_order;
END $$;

-- cancel_order: cancels an active order and releases what it still
-- reserves. p_user_id = NULL is a system cancellation (no ownership check).
CREATE OR REPLACE FUNCTION project.cancel_order(p_order_id uuid, p_user_id uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    o     project.orders%ROWTYPE;
    v_rem numeric;
BEGIN
    SELECT * INTO o FROM project.orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'order % does not exist', p_order_id USING ERRCODE = 'no_data_found';
    END IF;
    IF p_user_id IS NOT NULL AND o.user_id <> p_user_id THEN
        RAISE EXCEPTION 'order % does not belong to this user', p_order_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF o.status NOT IN ('open', 'partially_filled') THEN
        RAISE EXCEPTION 'order % is % and cannot be cancelled', p_order_id, o.status
            USING ERRCODE = 'check_violation';
    END IF;

    v_rem := o.quantity - o.filled_quantity;
    IF o.side = 'buy' THEN
        UPDATE project.users
           SET reserved_balance  = reserved_balance  - project.order_reservation(v_rem, o.price),
               available_balance = available_balance + project.order_reservation(v_rem, o.price),
               updated_at        = now()
         WHERE id = o.user_id;
    ELSE
        UPDATE project.holdings h
           SET reserved_quantity = h.reserved_quantity - v_rem, updated_at = now()
          FROM project.markets m
         WHERE m.id = o.market_id AND h.user_id = o.user_id AND h.crypto_id = m.crypto_id;
    END IF;

    UPDATE project.orders SET status = 'cancelled' WHERE id = p_order_id;
END $$;

-- ============================================================================
-- 6. VIEWS
-- ============================================================================

-- Active orders with what they still need and what they hold in reserve.
CREATE VIEW project.v_active_orders AS
SELECT o.id            AS order_id,
       o.user_id,
       u.username,
       o.market_id,
       c.symbol,
       m.quote_currency,
       o.side,
       o.type,
       o.status,
       o.quantity,
       o.filled_quantity,
       o.quantity - o.filled_quantity AS remaining,
       o.price,
       CASE WHEN o.side = 'buy'
            THEN project.order_reservation(o.quantity - o.filled_quantity, o.price) ELSE 0 END AS reserved_cash,
       CASE WHEN o.side = 'sell' THEN o.quantity - o.filled_quantity ELSE 0 END             AS reserved_crypto,
       o.placed_at
FROM project.orders o
JOIN project.users   u ON u.id = o.user_id
JOIN project.markets m ON m.id = o.market_id
JOIN project.crypto  c ON c.id = m.crypto_id
WHERE o.status IN ('open', 'partially_filled');

-- Current order book: resting limit orders aggregated per price level.
CREATE VIEW project.v_order_book AS
SELECT market_id,
       symbol,
       quote_currency,
       side,
       price,
       SUM(remaining) AS quantity,
       COUNT(*)       AS orders
FROM project.v_active_orders
WHERE type = 'limit'
GROUP BY market_id, symbol, quote_currency, side, price;

-- Every order with its fill progress and average fill price from its trades.
CREATE VIEW project.v_order_history AS
SELECT o.id            AS order_id,
       o.user_id,
       u.username,
       c.symbol,
       o.side,
       o.type,
       o.status,
       o.quantity,
       o.filled_quantity,
       o.quantity - o.filled_quantity AS remaining,
       o.price,
       f.trades,
       f.avg_fill_price,
       o.placed_at,
       o.executed_at
FROM project.orders o
JOIN project.users   u ON u.id = o.user_id
JOIN project.markets m ON m.id = o.market_id
JOIN project.crypto  c ON c.id = m.crypto_id
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS trades,
           round(SUM(t.quantity * t.price) / NULLIF(SUM(t.quantity), 0), 6) AS avg_fill_price
      FROM (SELECT quantity, price FROM project.market_trades WHERE buy_order_id  = o.id
            UNION ALL
            SELECT quantity, price FROM project.market_trades WHERE sell_order_id = o.id) t
) f ON true;

-- Trader balances: cash split into free and reserved, the ledger it must
-- equal, holdings at market value, and net worth.
CREATE VIEW project.v_trader_balances AS
SELECT u.id                         AS user_id,
       u.username,
       u.available_balance,
       u.reserved_balance,
       u.available_balance + u.reserved_balance              AS total_cash,
       COALESCE(l.ledger_total, 0)                           AS ledger_total,
       u.invested_balance,
       COALESCE(p.holdings_value, 0)                         AS holdings_value,
       u.available_balance + u.reserved_balance + COALESCE(p.holdings_value, 0) AS net_worth
FROM project.users u
LEFT JOIN (SELECT user_id, SUM(amount) AS ledger_total
             FROM project.transactions GROUP BY user_id) l ON l.user_id = u.id
LEFT JOIN (SELECT user_id, SUM(market_value) AS holdings_value
             FROM project.v_portfolio GROUP BY user_id) p ON p.user_id = u.id;

-- ============================================================================
-- 7. BACKGROUND JOB
-- ============================================================================

-- EduBerza's market price moves with the simulator (bots/main.go), not with
-- user orders. A resting limit order - buy at or above, or sell at or below,
-- the current market price - must then be filled by the simulated market,
-- just as it would have been had the price already been there when it was
-- placed. Nothing else happens at that moment that a trigger could react to
-- (the bot's price ticks deliberately stay cheap inserts), so this runs as a
-- periodic job: the bot process calls it after every round of price ticks.
-- The faculty server has no pg_cron, so the scheduling is done there.
-- An advisory lock keeps two runs from filling the same orders twice;
-- SKIP LOCKED leaves any order a user is cancelling right now for next time.
-- Returns the number of orders filled.
CREATE OR REPLACE FUNCTION project.fill_marketable_orders()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
    r       record;
    v_count int := 0;
BEGIN
    IF NOT pg_try_advisory_xact_lock(hashtext('project.fill_marketable_orders')) THEN
        RETURN 0;
    END IF;
    FOR r IN
        SELECT o.id, o.side, o.quantity - o.filled_quantity AS remaining, lp.price AS market_price
          FROM project.orders o
          JOIN project.markets m ON m.id = o.market_id AND m.is_active
          CROSS JOIN LATERAL (SELECT project.latest_price(o.market_id) AS price) lp
         WHERE o.type = 'limit'
           AND o.status IN ('open', 'partially_filled')
           AND (o.side = 'buy'  AND o.price >= lp.price
             OR o.side = 'sell' AND o.price <= lp.price)
         ORDER BY o.placed_at, o.id
           FOR UPDATE OF o SKIP LOCKED
    LOOP
        IF r.side = 'buy' THEN
            PERFORM project.execute_trade(r.id, NULL, r.remaining, r.market_price, 'sell');
        ELSE
            PERFORM project.execute_trade(NULL, r.id, r.remaining, r.market_price, 'buy');
        END IF;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END $$;
