# Advanced Database Development

EduBerza's users trade virtual money and virtual crypto with each other and with a simulated
market. Up to P6 the prototype only knew market orders that filled immediately against the
latest price, so an order was either untouched or completely done. This phase adds what makes an
exchange consistent once orders can **wait in an order book, fill in parts, and trade with each
other**, and puts every rule that keeps orders, trades and balances in agreement into the
database itself — so it holds no matter who writes the data (the CLI, the market bot, a script,
or someone typing SQL in DBeaver).

Only rules that span several rows or several tables are listed. `NOT NULL`, `UNIQUE`, `CHECK`,
primary and foreign keys are P2 ([RelationalDesign](../P2-RelationalDesign/RelationalDesign.md))
and are not presented as P7 features.

All of it is in [`server/db/advanced_db.sql`](../../server/db/advanced_db.sql), run by `-init`
between `schema_creation.sql` and `data_load.sql`. Every rule is exercised by
[`server/db/advanced_db_tests.sql`](../../server/db/advanced_db_tests.sql) (see
[Tests](#tests-proving-the-rules)).

## Overview

| # | Requirement | Triggers | Procedures / functions | Views | Tables affected |
|---|---|---|---|---|---|
| 1 | [Order lifecycle and filled/remaining consistency](#order-lifecycle-and-filledremaining-consistency) | `orders_lifecycle` | | | `orders` |
| 2 | [Trade consistency](#trade-consistency) | `market_trades_validate`, `market_trades_fill`, `market_trades_immutable` | `execute_trade` | | `market_trades`, `orders`, `users`, `holdings`, `transactions` |
| 3 | [Balance and reservation consistency](#balance-and-reservation-consistency) | `reserved_cash_matches_orders`, `reserved_crypto_matches_orders`, `cash_matches_ledger` (deferred) | `order_reservation` | | `users`, `holdings`, `orders`, `transactions` |
| 4 | [Placing and cancelling orders](#placing-and-cancelling-orders) | | `place_order`, `match_order`, `cancel_order` | | all of the above |
| 5 | [Automatic recording of order events](#automatic-recording-of-order-events) | `orders_events` | | | `order_events` (new) |
| 6 | [Views for derived trading data](#views-for-derived-trading-data) | | | `v_order_book`, `v_active_orders`, `v_order_history`, `v_trader_balances` | read-only |
| 7 | [Background job: filling resting limit orders](#background-job-filling-resting-limit-orders) | | `fill_marketable_orders` | | `orders`, `market_trades`, … |

### Schema additions

The existing design had no place for three things the requirements need, so four columns were
added — nothing else in the design changed:

| Column | Why it is needed |
|---|---|
| `orders.filled_quantity` (+ status value `partially_filled`) | "filled / remaining quantity" cannot be kept consistent without storing how much was filled; remaining = `quantity − filled_quantity` |
| `users.reserved_balance` | cash committed to open buy orders must be set aside somewhere; `holdings.reserved_quantity` already did this for crypto on sell orders |
| `market_trades.buy_order_id`, `market_trades.sell_order_id` | "a trade can only happen between compatible orders" needs the trade to say which orders it filled. `NULL` on a side means the simulated market was the counterparty; the bot's price ticks have both `NULL` |

One new table, `order_events`, holds the automatically recorded events (requirement 5).

## Order lifecycle and filled/remaining consistency

### Data requirements description

**Business rule.**

- An order's status follows from how much of it has been filled: nothing filled → `open`,
  partly filled → `partially_filled`, completely filled → `executed`. The only status that is
  set explicitly is `cancelled`, and only on an order that is still active.
- `executed` and `cancelled` are final — such an order can never be processed again (no further
  fills, no cancellation, no changes).
- `filled_quantity` only grows, never exceeds `quantity`, and only changes when a trade fills
  the order.
- What was ordered — user, market, side, type, quantity, price, time of placement — never
  changes after placement.
- `executed_at` is set exactly when the order becomes `executed`.
- New orders are only accepted on active markets, need a positive price, and start unfilled
  (the one exception is importing an order that was completely executed in the past, used by the
  sample data).

**Why it is non-trivial.** The rule compares the *old* and the *new* version of a row (valid
transitions, "final" states, "only grows", immutable columns) and ties two columns together
(status ↔ filled quantity). A `CHECK` constraint only sees one version of one row. It also
depends on *who* changes `filled_quantity` — a trade may, a manual `UPDATE` may not.

**PostgreSQL feature.** `BEFORE INSERT OR UPDATE` row trigger on `orders`. The trade trigger
(requirement 2) sets a transaction-local setting (`set_config('eduberza.trade_fill', 'on', true)`)
while it fills an order; the lifecycle trigger only accepts a change of `filled_quantity` when
that setting is on.

**Tables affected.** `orders` (reads `markets` for the active check).

### Implementation

#### Triggers

```sql
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
```

Because the status is derived, the application never sets `open`, `partially_filled` or
`executed` itself — it records trades, and the status follows.

## Trade consistency

### Data requirements description

**Business rule.** A trade that fills orders must be possible for those orders:

- the buy side is a buy order and the sell side is a sell order;
- both are on the trade's market and still active — a cancelled or executed order can never
  trade again;
- the trade quantity does not exceed the remaining quantity of either order;
- the price respects both limits: at most the buy order's price, at least the sell order's price;
- the two orders belong to different users (no self-trade).

Recording the trade must fill both orders by exactly the traded quantity (and so move their
status), and move the money and crypto for both users, all together. A trade that filled orders
is history and can't be changed or deleted afterwards — the fills and the money moved would no
longer match it.

**Why it is non-trivial.** One trade row has to be checked against two other rows of another
table (the orders), including their current remaining quantity, and a single insert must cause
consistent changes in five tables (`market_trades`, both `orders`, both users' `users` and
`holdings` rows, two `transactions` rows).

**PostgreSQL features.**

- `BEFORE INSERT` trigger `market_trades_validate` — the compatibility rules. It locks both
  orders (`FOR UPDATE`), so two concurrent trades can't both take the same remaining quantity.
- `AFTER INSERT` trigger `market_trades_fill` — raises `filled_quantity` on both orders
  (automatic status change through requirement 1).
- `BEFORE UPDATE OR DELETE` trigger `market_trades_immutable`.
- Stored function `execute_trade` — the settlement of money and crypto for one trade.

Because the rules sit on `market_trades` itself, even a trade inserted by hand is validated and
fills the orders.

**Tables affected.** `market_trades`, `orders`, `users`, `holdings`, `transactions`.

### Implementation

#### Triggers

```sql
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
```

```sql
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
```

```sql
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
```

#### Stored procedures/functions

`execute_trade(buy_order, sell_order, quantity, price)` — one trade. Either order may be `NULL`
when the simulated market is the counterparty. The `INSERT` into `market_trades` validates the
trade and fills the orders (triggers above); the function then settles both users:

- **Buyer:** the reservation for the filled part is released. The buyer pays the actual cost
  (trade price × quantity); if the trade price is below the order's limit, the difference goes
  back to `available_balance`. The crypto is added to the holding at a running weighted average
  price, and a `buy` ledger row is written.
- **Seller:** the reserved crypto is delivered out of the holding, the proceeds are credited, the
  cost basis is removed from `invested_balance`, and a `sell` ledger row is written.

Both orders are locked in a fixed order (by id), so two trades on the same pair of orders can't
deadlock.

```sql
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
```

## Balance and reservation consistency

### Data requirements description

**Business rule.**

1. **Reserved cash matches active buy orders.** A user's `reserved_balance` always equals what
   their active buy orders still reserve: remaining quantity × order price, summed.
2. **Reserved crypto matches active sell orders.** A user's `holdings.reserved_quantity` for a
   crypto always equals the remaining quantity of their active sell orders for it.
3. **Cash matches the ledger.** `available_balance + reserved_balance` always equals the sum of
   the user's ledger (`transactions`). Reserving only moves cash between the two columns; money
   actually arrives or leaves only with a ledger row (deposit, buy fill, sell fill).

Together these make it impossible for an order operation to leave a balance in an inconsistent
state: money or crypto reserved for nothing, an order that is not backed by a reservation (and
so could spend the same money twice), or cash that appeared or vanished without a ledger entry.

**Why it is non-trivial.** Each rule is an equality between a column and an aggregate over
*other* rows of *other* tables. Worse, every legitimate operation breaks it for a moment:
placing a buy moves cash to `reserved_balance` in one statement and inserts the order in the
next; a trade releases the reservation, pays, and writes the ledger in several statements. Only
the state at the end of the transaction has to be consistent.

**PostgreSQL feature.** `CONSTRAINT TRIGGER … DEFERRABLE INITIALLY DEFERRED` — row triggers
whose check runs at `COMMIT`, on the final state. A transaction that leaves any of the three
equalities broken fails at `COMMIT` and is rolled back as a whole. Each rule has a trigger on
every table whose change can break it. `order_reservation(remaining, price)` is the one place
that defines how a reservation is rounded, so placing, filling, cancelling and checking always
agree to the last decimal.

**Tables affected.** `users`, `holdings`, `orders`, `transactions`.

### Implementation

#### Stored procedures/functions

```sql
CREATE OR REPLACE FUNCTION project.order_reservation(p_remaining numeric, p_price numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT round(p_remaining * p_price, 4)
$$;
```

#### Triggers

```sql
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
```

```sql
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
```

```sql
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
```

```sql
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
```

The partial index `idx_orders_active` covers exactly the rows the reservation checks sum, and
stays small because active orders are few compared with the whole order history.

## Placing and cancelling orders

### Data requirements description

**Business rule.** Placing an order must, as one unit:

1. check the market, side, type, quantity and price;
2. reserve what the order commits — cash (quantity × price) for a buy, crypto for a sell — and
   refuse the order if not enough is free;
3. record the order;
4. match it against the order book: other users' active limit orders on the same market whose
   price is acceptable, best price first and oldest first (price–time priority), each trade at
   the resting order's price;
5. fill whatever is still unfilled from the simulated market if it is marketable at the current
   market price.

A **market order** is priced at the current market price, so it always fills completely in step
4 or 5 and never waits. A **limit order** that isn't marketable stays in the order book.
Cancelling an order must release exactly what it still reserves, and only for an active order of
the caller.

**Why it is non-trivial.** It is a multi-step operation over five tables whose steps depend on
each other (how much is left after each match, what to release), and it has to be correct under
concurrency: two orders of the same user must not both see the same free cash.

**PostgreSQL feature.** Stored functions (PL/pgSQL). `place_order` locks the user's row
(`SELECT … FOR UPDATE`) before checking free cash or crypto, so concurrent orders of the same
user are serialised. Every step's consistency is still checked by the triggers of requirements
1–3.

**Tables affected.** `orders`, `users`, `holdings`, `market_trades`, `transactions`.

### Implementation

#### Stored procedures/functions

```sql
CREATE OR REPLACE FUNCTION project.latest_price(p_market_id uuid)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT price FROM project.market_trades
     WHERE market_id = p_market_id
     ORDER BY executed_at DESC, id DESC
     LIMIT 1
$$;
```

```sql
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
```

```sql
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
```

```sql
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
```

In the prototype, placing an order is now a single call:

```go
err = db.DB.QueryRow(
	`SELECT place_order($1, $2, $3, $4, $5, $6)`,
	s.UserID, m.ID, side, orderType, qty, limit.value(),
).Scan(&orderID)
```

Cancelling is `SELECT cancel_order($1, $2)` with the order the user picked from a numbered list
of their open orders ([`server/trade.go`](../../server/trade.go)).

## Automatic recording of order events

### Data requirements description

**Business rule.** Every important thing that happens to an order is recorded with its time:
placement, each fill (with the quantity filled and the trade price), and cancellation. This is
the order's audit trail — the history of *how* it reached its current state, which the order row
alone (only the current state) cannot show.

**Why it is non-trivial.** Events come from several places — `place_order`, trades made by
`match_order`, trades made by the background job, `cancel_order`, and any direct SQL. Recording
them in each of those places would miss some; recording them where the change actually happens
cannot.

**PostgreSQL feature.** `AFTER INSERT OR UPDATE` row trigger on `orders`, writing into the new
table `order_events`. The fill price is handed over by the trade trigger through a
transaction-local setting.

**Tables affected.** `order_events` (new), written from changes to `orders`.

### Implementation

```sql
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
```

#### Triggers

```sql
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
```

## Views for derived trading data

### Data requirements description

The application needs several things that are *derived* from orders, trades and balances. They
are defined once as views, instead of repeating the calculations in the application code:

| View | Derived data | Used by |
|---|---|---|
| `v_active_orders` | active orders with remaining quantity and what each one holds in reserve | CLI `[13] My open orders`, `[14] Cancel an order` |
| `v_order_book` | current order book: resting limit orders aggregated per market, side and price level | CLI `[12] Order book`, and when placing an order |
| `v_order_history` | every order with its fill progress, number of trades and average fill price (from its trades) | CLI result of placing an order |
| `v_trader_balances` | cash split into available and reserved, the ledger total it must equal, holdings at market value, net worth | CLI `[1] View balance` |

None of these repeats a P6 report: P6 aggregates performance over a period, while these show
the current state of the order book and accounts.

### Implementation

#### Views

```sql
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
```

```sql
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
```

```sql
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
```

```sql
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
```

## Background job: filling resting limit orders

### Data requirements description

**Business rule.** In EduBerza the market price is moved by the simulator (the market bot), not
by users' orders. A limit order that rests in the book — a buy at or above, or a sell at or
below, the current market price — must then be filled by the simulated market, at the market
price, just as it would have been had the price already been there when the order was placed.

**Why it is relevant, and why a background job.** Without it, a limit order could only ever
fill against another user's order, and with few users most limit orders would wait forever while
the market price has long passed them. That would make limit orders useless in the simulation.
Nothing happens at the moment the price crosses an order that a trigger could react to: the
price moves through the bot's inserts into `market_trades`, which deliberately stay cheap single
inserts. Scanning and filling every crossed order on every tick inside that insert would make
each tick expensive. So the work runs as a periodic job after each round of price ticks.

**PostgreSQL feature.** Stored function `fill_marketable_orders()`. It is scheduled by the
application, because PostgreSQL has no built-in scheduler and the faculty server provides no
`pg_cron` (checked: only `plpgsql` and `pgcrypto` are available, and the project role is not a
superuser).

- An advisory lock (`pg_try_advisory_xact_lock`) keeps two runs from filling the same orders
  twice.
- `FOR UPDATE … SKIP LOCKED` leaves alone an order a user is cancelling at that moment; the next
  run picks it up.
- Every fill goes through `execute_trade`, so all the rules above apply to it.

**Tables affected.** `orders`, `market_trades`, `users`, `holdings`, `transactions`,
`order_events`.

### Implementation

#### Stored procedures/functions

```sql
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
```

#### Scheduling

In [`bots/main.go`](../../bots/main.go), after every round of price ticks:

```go
// P7 background job: the prices just moved, so fill any resting
// limit order the new market price has reached.
var filled int
if err := db.QueryRow(`SELECT fill_marketable_orders()`).Scan(&filled); err != nil {
	log.Printf("fill_marketable_orders: %v", err)
} else if filled > 0 {
	log.Printf("  filled %d resting limit order(s) at the new market price", filled)
}
```

It can also be run by hand from any SQL client: `SELECT project.fill_marketable_orders();`.

A run with the bot, after charlie placed a limit buy of 0.1 ETH at 3599 while the market was at
3600: the bot's random walk took the price below 3599 and the job filled the order at the market
price.

```
2026/09/24 13:19:02   filled 1 resting limit order(s) at the new market price
```

```
 username | side | type  |  status   | quantity | filled_quantity |    price    | avg_fill_price
----------+------+-------+-----------+----------+-----------------+-------------+----------------
 charlie  | buy  | limit | cancelled |   0.1000 |          0.0000 | 3400.000000 |
 charlie  | buy  | limit | executed  |   0.1000 |          0.1000 | 3599.000000 |    3593.979167
```

## Tests proving the rules

[`server/db/advanced_db_tests.sql`](../../server/db/advanced_db_tests.sql) plays a short trading
story on the sample data and, along the way, tries to break every rule. It starts from alice with
8250 USD and 0.5 ETH, bob with 5000 USD, charlie with 2500 USD, and ETH/USD last traded at 3520:

1. alice places a limit sell of 0.3 ETH at 3600, and bob a limit buy of 0.1 at 3500. Both rest in
   the book.
2. bob places a limit buy of 0.2 at 3650. It crosses alice's ask, so they trade 0.2 at 3600:
   alice's order becomes partially filled, and bob gets back the 10 he had reserved above the
   trade price.
3. charlie places a market buy of 0.15. He takes alice's remaining 0.1 from the book, and the
   other 0.05 comes from the simulated market.
4. Invalid trades, state changes and balance changes are attempted directly in SQL.
5. bob cancels his bid.
6. The simulator moves the price to 3450, and the background job fills bob's new limit buy at
   3500.

The deferred checks are forced with `SET CONSTRAINTS ALL IMMEDIATE`, so a violation shows up
inside the test instead of at the final `COMMIT`. Everything is rolled back at the end. Run on
PostgreSQL 17 after `-init`:

```
PASS  place: limit sell above the market rests in the book, crypto reserved: alice ETH reserved = 0.3000
PASS  place: limit buy below the market rests in the book, cash reserved: bob available 4650.0000 reserved 350.0000
PASS  event: placement recorded automatically:
PASS  view: order book shows both price levels: buy 0.1000 @ 3500.000000, sell 0.3000 @ 3600.000000
PASS  consistency holds after placing:
PASS  place: buy without enough free cash: insufficient funds: the order needs 60000.0000, available 2500.0000
PASS  place: sell more than is free (0.2 of 0.5 is already reserved): insufficient holding: trying to sell 0.3, free to sell 0.2000
PASS  match: trade between the two orders at the resting price:
PASS  status: seller partially filled, buyer executed (automatic): alice_ask partially_filled 0.2000/0.3000
PASS  money: buyer paid 720, got back the 10 reserved above the trade price: bob available 3930.0000 reserved 350.0000
PASS  crypto: 0.2 ETH moved from alice (0.1 still reserved) to bob:
PASS  ledger: one buy and one sell row, linked to the orders:
PASS  event: fills recorded automatically:
PASS  consistency holds after the trade:
PASS  market order: filled completely in two trades: executed, 2 trades, avg 3600.000000
PASS  market order: alice's ask is now executed, nothing left reserved:
PASS  consistency holds after the market order:
PASS  trade: price above the buyer's limit: trade price 3700.000000 is outside the limit 3500.000000 of buy order …
PASS  trade: more than the order has remaining: trade quantity 0.500000 exceeds the remaining quantity 0.1000 of order …
PASS  trade: a sell order used as the buy side: order … is a sell order and cannot be the buy side of a trade
PASS  trade: order of another market: order … is on a different market than the trade
PASS  trade: executed order cannot trade again: order … is executed and cannot trade
PASS  trade: a user with their own order: a user cannot trade with their own order
PASS  trade: a trade that filled orders cannot be deleted: a trade that filled orders cannot be changed or deleted
PASS  state: status cannot be set to executed by hand: order status executed does not match filled quantity 0.0000 of 0.1000; status is derived automatically
PASS  state: filled quantity cannot be changed by hand: filled quantity of order … can only change through a trade
PASS  state: executed order cannot be processed again: order … is already executed and cannot be processed again
PASS  state: ordered quantity cannot change: user, market, side, type, quantity, price and placed_at of an order cannot change
PASS  state: cancelling by hand without releasing the reservation: reserved balance 350.0000 does not match the 0 needed by active buy orders (user …)
PASS  cancel: someone else's order: order … does not belong to this user
PASS  cancel: 350 back from reserved to available, event recorded: bob available 4280.0000 reserved 0.0000
PASS  cancel: a cancelled order cannot be cancelled again: order … is cancelled and cannot be cancelled
PASS  trade: cancelled order cannot trade: order … is cancelled and cannot trade
PASS  balance: reserving cash with no order behind it: reserved balance 100.0000 does not match the 0 needed by active buy orders (user …)
PASS  balance: reserving crypto with no order behind it: reserved quantity 0.0100 does not match the 0 needed by active sell orders (user …, crypto …)
PASS  balance: cash changed without a ledger row: cash 2060.0000 (available + reserved) does not match the ledger total 1960.0000 (user …)
PASS  job: fills exactly the orders the new price reached: bob_bid3 executed @ 3450.000000, charlie_ask (3700) still open
PASS  job: buyer paid 345, got the 5 above the fill price back:
PASS  job: nothing more to do on a second run:
PASS  consistency holds after the job:
PASS  views: every trader's cash equals their ledger:

 passed | failed
--------+--------
     41 |      0
```

The same rules seen from the prototype (bob, after alice put 0.3 ETH up for sale at 3600):

```
-- Place buy order --
Latest price for ETH/USD = 3520.000000
Order book asks (other users' limit orders):
     3600.000000        0.3000  (1 orders)
[1] Market order (fills now at the best available price)
[2] Limit order (fills only at your price or better, otherwise waits in the order book)
> 2
Quantity: 0.2
Limit price: 3650
Order executed: buy 0.2000 ETH, average price 3600.000000
```

## Changes to earlier phases

- **Schema** ([RelationalDesign](../P2-RelationalDesign/RelationalDesign.md), [ERModel](../P1-ConceptualModel/ERModel.md)):
  - `users.reserved_balance`;
  - `orders.filled_quantity` and the status value `partially_filled`;
  - `market_trades.buy_order_id` / `sell_order_id` (optional references to `orders` — a new
    relationship "trade fills order");
  - the new table `order_events`.
- **Sample data** (`data_load.sql`):
  - deposit rows for bob and charlie, whose balances previously had no ledger entries behind
    them;
  - alice's seeded order is imported as completely filled;
  - the script runs as one transaction.

  The balances documented in [BuildInstructions](../P4-Prototype/BuildInstructions.md) are
  unchanged.
- **P6 demo data** (`reports_demo_data.sql`): it adjusts the users' balances by exactly what it
  adds to the ledger, and imports its orders as completely filled. Both
  [AdvancedReports](../P6-AdvancedReports/AdvancedReports.md) outputs are unchanged.
- **Prototype:**
  - placing an order is one call to `place_order`, and market or limit can be chosen;
  - new menu items `[12] Order book`, `[13] My open orders`, `[14] Cancel an order`;
  - the balance screen shows reserved cash;
  - the bot runs the background job.

## AI usage

AI was used in this phase and is logged in full, per the course rule for P1 onward.

- **Phase log:** [AdvancedDatabaseDevelopmentAIUsage.md](AdvancedDatabaseDevelopmentAIUsage.md)

**In short:** the requirements — order state consistency, filled/remaining quantities, reserved
money and assets, trades only between compatible orders, the kinds of triggers, procedures and
views, and a background job only if relevant — were mine. I asked the AI to turn them into
concrete rules for the existing EduBerza database, implement them without redesigning it, test
them and document them.
