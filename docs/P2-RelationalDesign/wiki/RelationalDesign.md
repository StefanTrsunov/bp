= Relational Design =

This page transforms [wiki:ERModel] '''v05''' into
relations. Every relation below corresponds to exactly one entity set of the
model, and every foreign key corresponds to exactly one relationship, so the
two diagrams can be compared box for box and line for line (see
Relational diagram).

== Descriptive representation of the relational schema ==

Notation: '''bold''' = primary key, ''italic'' = foreign key. After each foreign key
comes the ER relationship it implements.

 * '''Users'''(__'''id'''__, username, email, full_name, password_hash, available_balance, invested_balance, reserved_balance, created_at, updated_at)
   * Entity set `Users`. Candidate keys: `{id}`, `{username}`, `{email}`. `UNIQUE(username)`, `UNIQUE(email)`.
 * '''Crypto'''(__'''id'''__, symbol, name, created_at)
   * Entity set `Cryptos`. Candidate keys: `{id}`, `{symbol}`. `UNIQUE(symbol)`.
 * '''Markets'''(__'''id'''__, ''crypto_id'' [`QuotedOn`], quote_currency, is_active, created_at)
   * Entity set `Markets`. Candidate keys: `{id}`, `{crypto_id, quote_currency}` (the model's rule "a crypto is quoted at most once per currency"), enforced with `UNIQUE(crypto_id, quote_currency)`.
 * '''Holdings'''(__'''id'''__, ''user_id'' [`Holds`], ''crypto_id'' [`PositionIn`], quantity, reserved_quantity, avg_price, created_at, updated_at)
   * Entity set `Holdings`. Candidate keys: `{id}` and `{user_id, crypto_id}` (the model's rule "one holding per user and crypto"), enforced with `UNIQUE(user_id, crypto_id)`.
   * `avg_price` is `NOT NULL DEFAULT 0 CHECK (avg_price >= 0)`.
   * `reserved_quantity` is `NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0 AND reserved_quantity <= quantity)` — the amount already committed to the user's own open sell orders. `quantity - reserved_quantity` (the amount actually free to sell) is not a stored column; it is computed wherever needed, in `v_portfolio` as `available_quantity` and in the sell path of [wiki:UseCase0005]. See [wiki:ERModel] (section "Holdings") for why this mirrors `available_balance`/`invested_balance` on `Users`.
 * '''Orders'''(__'''id'''__, ''user_id'' [`Places`], ''market_id'' [`PlacedOn`], side, type, status, quantity, filled_quantity, price, placed_at, executed_at)
   * Entity set `Orders`. `side ∈ {buy, sell}`, `type ∈ {market, limit}`, `status ∈ {open, partially_filled, executed, cancelled}`, `0 ≤ filled_quantity ≤ quantity`.
 * '''Transactions'''(__'''id'''__, ''user_id'' [`Records`], type, amount, currency, ''related_order'' [`Settles`], created_at, description)
   * Entity set `Transactions`. `type ∈ {deposit, buy, sell, fee}`. `related_order` is nullable (see below).
 * '''!MarketTrades'''(__'''id'''__, ''market_id'' [`Fills`], executed_at, price, quantity, side, source, ''buy_order_id'' [`FillsBuy`], ''sell_order_id'' [`FillsSell`])
   * Entity set `MarketTrades`. `buy_order_id` and `sell_order_id` are both nullable (see below).
 * '''!OrderEvents'''(__'''id'''__, ''order_id'' [`Logs`], event_type, quantity, price, status_after, created_at)
   * Entity set `OrderEvents`. `event_type ∈ {placed, partially_filled, filled, cancelled}`.
 * '''!MarketCandles'''(__'''id'''__, ''market_id'' [`Aggregates`], timeframe, open, high, low, close, volume, candle_time)
   * Entity set `MarketCandles`. Candidate keys: `{id}`, `{market_id, timeframe, candle_time}` (the model's rule "one candle per market, timeframe and bucket"), enforced with `UNIQUE(market_id, timeframe, candle_time)`.
 * '''Watchlists'''(__'''id'''__, ''user_id'' [`Owns`], name, created_at)
   * Entity set `Watchlists`.
 * '''!WatchlistItems'''(__'''id'''__, ''watchlist_id'' [`Contains`], ''crypto_id'' [`Lists`], added_at)
   * Entity set `WatchlistItems`. Candidate keys: `{id}` and `{watchlist_id, crypto_id}` (the model's rule "an asset at most once per list"), enforced with `UNIQUE(watchlist_id, crypto_id)`.

=== Transformation method used ===

'''Partial transformation.''' The model has 11 entity sets and 15 relationships.
Every relationship is binary and 1:N with no attributes of its own (the two M:N
relationships of earlier versions, `Holds` and `Contains`, were corrected into
the entity sets `Holdings` and `WatchlistItems` in v05). The rules:

 * '''Each entity set becomes one relation''', with its own attributes and its own key `id` as primary key. 11 entity sets → 11 relations.
 * '''Each 1:N relationship becomes one foreign key''' on the relation of the "N" side, pointing to the primary key of the "1" side. No relationship gets its own table, because none is M:N and none has attributes. 15 relationships → 15 foreign keys:

  ||= ER relationship =||= 1 side → N side =||= Foreign key =||= Participation of the N side =||= `NULL`? =||
  || `QuotedOn` || Cryptos → Markets || `markets.crypto_id` || total || `NOT NULL` ||
  || `PlacedOn` || Markets → Orders || `orders.market_id` || total || `NOT NULL` ||
  || `Places` || Users → Orders || `orders.user_id` || total || `NOT NULL` ||
  || `Records` || Users → Transactions || `transactions.user_id` || total || `NOT NULL` ||
  || `Settles` || Orders → Transactions || `transactions.related_order` || partial || nullable ||
  || `Fills` || Markets → !MarketTrades || `market_trades.market_id` || total || `NOT NULL` ||
  || `FillsBuy` || Orders → !MarketTrades || `market_trades.buy_order_id` || partial || nullable ||
  || `FillsSell` || Orders → !MarketTrades || `market_trades.sell_order_id` || partial || nullable ||
  || `Logs` || Orders → !OrderEvents || `order_events.order_id` || total || `NOT NULL` ||
  || `Aggregates` || Markets → !MarketCandles || `market_candles.market_id` || total || `NOT NULL` ||
  || `Owns` || Users → Watchlists || `watchlists.user_id` || total || `NOT NULL` ||
  || `Holds` || Users → Holdings || `holdings.user_id` || total || `NOT NULL` ||
  || `PositionIn` || Cryptos → Holdings || `holdings.crypto_id` || total || `NOT NULL` ||
  || `Contains` || Watchlists → !WatchlistItems || `watchlist_items.watchlist_id` || total || `NOT NULL` ||
  || `Lists` || Cryptos → !WatchlistItems || `watchlist_items.crypto_id` || total || `NOT NULL` ||

 * '''Participation decides `NULL`.''' Total participation of the N side means every row must reference a parent, so the foreign key is `NOT NULL`. Partial participation leaves it nullable. There are exactly three partial ones: `Settles` (a deposit has no originating order), and `FillsBuy` / `FillsSell` (a trade against the simulated market has no user order on that side). Partial participation of the '''1''' side (for example, a user with no orders) needs no column at all. It simply means no row points at that parent.
 * '''Uniqueness rules of the model become `UNIQUE` constraints.''' The four rules the model states in words ("a crypto quoted once per currency", "one candle per market, timeframe and bucket", "one holding per user and crypto", "an asset once per list") involve a relationship, so Chen notation cannot draw them as keys. After transformation, the relationship is a foreign-key column, and each rule becomes an ordinary composite `UNIQUE` constraint, i.e. a second candidate key.

Nothing in the schema comes from anywhere else. Every column is either an ER
attribute or the foreign key of one listed relationship.

=== Normalisation ===

> '''Checked in P5.''' [wiki:Normalization]
> starts from a single de-normalized relation containing only the attributes
> of the ER model and the functional dependencies that follow from its rules.
> It decomposes that relation step by step to BCNF and arrives at these same 11
> relations, with one deliberate difference: `transactions.user_id` (see the last
> bullet below). The comparison is in the ''Discussion'' section at the end of that
> page.

All relations except `transactions` are in '''BCNF''', as P5 shows. `transactions`
is in 2NF but not in 3NF, because of the deliberately kept `user_id` (last
bullet):

 * Every attribute is atomic (no repeating groups, no composite fields).
 * No partial dependency exists: every candidate key is either the single column `id` or a composite key (`{user_id, crypto_id}`, …) on which no non-key attribute depends only partially.
 * No transitive dependency exists, except `transactions.user_id` (last bullet): every other non-key attribute depends directly on the row's own entity, never on another entity reached through a foreign key. For example, `holdings.quantity` depends on `holdings.id`, and nothing about the user or the crypto is copied into `holdings`.
 * `avg_price` in `Holdings` is a '''derived value''' cached for performance (it is the weighted-average entry price across all `buy` transactions for that `(user, crypto)` pair) — it is drawn as a derived attribute in the ER diagram. We accept the denormalisation: it is recomputed by the database inside the same transaction as each buy, in the same statement that changes the quantity (`INSERT … ON CONFLICT (user_id, crypto_id) DO UPDATE`), so the stored average and the stored quantity can never disagree.
 * `avg_price` is declared `NOT NULL DEFAULT 0`. This matters: it is used in the P/L arithmetic of `v_portfolio`, and in SQL any arithmetic involving `NULL` yields `NULL`, so a nullable average would have silently blanked the unrealised-P/L column for an existing position instead of failing loudly.
 * `holdings.reserved_quantity`, unlike `avg_price`, is '''not''' derived — it is written directly by the application (`trade.go`) as orders are placed and settled, the same way `quantity` itself is. `quantity - reserved_quantity` ("available") is the derived value here, and it is never stored, only computed where it is needed.
 * `transactions.user_id` is kept '''deliberately''', although for an entry that settles an order it repeats that order's user (`related_order → user_id`, a transitive dependency). A deposit has no order (`Settles` is partial), so `user_id` is the only way to record whose deposit it is. For entries with an order, the only code that sets `related_order` (the buy and sell inserts in `advanced_db.sql`) writes both from the same order row. No database constraint enforces this.

=== Reservation and the order lifecycle ===

`holdings.reserved_quantity` exists so that placing a sell order can be
checked against what a user actually has ''free'' to sell
(`quantity - reserved_quantity`), not against the raw `quantity`, which also
counts crypto already promised to another order that has not settled yet.
`CHECK (reserved_quantity >= 0 AND reserved_quantity <= quantity)` makes an
inconsistent reservation impossible at the database level, regardless of what
application code does. The exact statement sequence — lock the row, check the
available amount, reserve, then settle — is in
[wiki:UseCase0005]; the same
`SELECT … FOR UPDATE` locking that already protected `users.available_balance`
on the buy path is what makes two concurrent sell orders against the same
holding serialize correctly instead of racing. The cash side of a buy order
(`users.reserved_balance`), `orders.filled_quantity` and `order_events` were
added in P7; see
[wiki:AdvancedDatabaseDevelopment].

== DDL script ==

The script that creates the schema is `../server/db/schema_creation.sql` (shown below). It is idempotent: it drops and recreates the `project` schema every run, so it works on an empty database and on a database that already has the schema.

The script creates:
 * 10 of the 11 tables, with check constraints, primary keys, foreign keys and unique constraints.
 * 8 performance indexes.
 * 2 views: `v_latest_prices` (latest trade price per market) and `v_portfolio` (per-user holdings valuation with unrealised P/L, plus `reserved_quantity` and the derived `available_quantity`).

The 11th table, `order_events`, is created by
`../server/db/advanced_db.sql` together with
the P7 triggers that fill it. `./eduberza -init` runs both scripts in that
order, so a freshly initialised database always has all 11 tables and all 15
foreign keys.

=== schema_creation.sql ===

The two report functions at the end of the file (`report_top_traders` and `report_market_performance`) belong to Phase 6 ([wiki:AdvancedReports]) and are left out here.

{{{
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
    -- P7: cash committed to the user's active buy orders, moved out of
    -- available_balance when the order is placed and consumed as it fills.
    reserved_balance  numeric(18,4)   NOT NULL DEFAULT 0 CHECK (reserved_balance  >= 0),
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
    status      varchar(20)    NOT NULL CHECK (status IN ('open', 'partially_filled', 'executed', 'cancelled')),
    quantity    numeric(20,4)  NOT NULL CHECK (quantity > 0),
    -- P7: how much of the order has been traded so far; remaining is
    -- quantity - filled_quantity. Maintained from market_trades.
    filled_quantity numeric(20,4) NOT NULL DEFAULT 0
                               CHECK (filled_quantity >= 0 AND filled_quantity <= quantity),
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
    source      varchar(50)    NOT NULL DEFAULT 'simulation',
    -- P7: the orders this trade filled. NULL on a side means the counterparty
    -- was the simulated market (bot ticks have both NULL).
    buy_order_id  uuid         REFERENCES project.orders(id),
    sell_order_id uuid         REFERENCES project.orders(id)
);

CREATE INDEX idx_market_trades_market_time ON project.market_trades(market_id, executed_at DESC);
CREATE INDEX idx_market_trades_buy_order  ON project.market_trades(buy_order_id)  WHERE buy_order_id  IS NOT NULL;
CREATE INDEX idx_market_trades_sell_order ON project.market_trades(sell_order_id) WHERE sell_order_id IS NOT NULL;

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
}}}

=== order_events (from advanced_db.sql) ===

{{{
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
}}}

== DML script (sample data) ==

The script that loads realistic sample data is `../server/db/data_load.sql` (shown below). It is idempotent: it truncates all tables with `CASCADE` then re-inserts. Loaded:
 * 5 crypto assets (BTC, ETH, ADA, SOL, DOGE) and 5 USD-quoted markets.
 * 3 sample users (`alice`, `bob`, `charlie`) with password `test123` (sha256 hex).
 * 18 recent market trades across all markets so `v_latest_prices` is populated.
 * 10 one-hour candles (BTC and ETH).
 * One fully-executed market-buy order for Alice, the matching holding, and two ledger entries (deposit + buy), with Alice's balances updated accordingly.
 * Two watchlists with five watchlist items.

=== data_load.sql ===

{{{
-- data_load.sql
-- EduBerza - sample data
-- Course: Databases 2025/2026 Winter, FINKI UKIM
--
-- Idempotent. Truncates all tables in the `project` schema and reloads
-- deterministic sample data. Run schema_creation.sql first if tables do
-- not yet exist.
--
-- All sample users have the password: test123
--
-- One transaction: the P7 checks in advanced_db.sql compare balances with
-- the ledger at COMMIT, and the users are inserted with their balances
-- before the deposit rows that back them. In an auto-commit client
-- (DBeaver) every statement would otherwise be checked on its own.

BEGIN;

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
-- Imported as already completely filled (filled_quantity = quantity).
INSERT INTO project.orders (id, user_id, market_id, side, type, status, quantity, filled_quantity, price, placed_at, executed_at) VALUES
    ('c1111111-1111-1111-1111-111111111111',
     'b1111111-1111-1111-1111-111111111111',
     'a2222222-2222-2222-2222-222222222222',
     'buy', 'market', 'executed', 0.5000, 0.5000, 3500.000000,
     now() - interval '1 hour', now() - interval '1 hour');

INSERT INTO project.holdings (user_id, crypto_id, quantity, avg_price, updated_at) VALUES
    ('b1111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222',
     0.5000, 3500.000000, now() - interval '1 hour');

INSERT INTO project.transactions (user_id, type, amount, currency, related_order, description) VALUES
    ('b1111111-1111-1111-1111-111111111111', 'deposit',  10000.0000, 'USD', NULL,
        'Initial virtual deposit'),
    ('b2222222-2222-2222-2222-222222222222', 'deposit',   5000.0000, 'USD', NULL,
        'Initial virtual deposit'),
    ('b3333333-3333-3333-3333-333333333333', 'deposit',   2500.0000, 'USD', NULL,
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

COMMIT;
}}}

== Relational diagram ==

[[Image(relational_diagram_v4.png, 800px)]]

Generated in '''DBeaver''' from the '''live''' `project` schema (after
`./eduberza -init`), not drawn by hand, so it shows what the deployed database
actually contains. Each box is a table with its columns; the key icon marks the
primary key, and the lines are the 15 declared foreign keys. The two foreign keys from
`market_trades` to `orders` (`buy_order_id`, `sell_order_id`) connect the same
two boxes, so DBeaver draws them on top of each other as one line.

The tables are arranged in the '''same positions''' as the entity sets in
`ERModel_v05.png`, so the two can be compared directly:

 * every rectangle of the ER diagram is one table in the same place;
 * every diamond of the ER diagram is one foreign-key line between the same two boxes. The dot is on the referencing ("N") table, next to the foreign-key column;
 * a double (total) line in the ER diagram is a `NOT NULL` foreign key, drawn by DBeaver as a solid line. The three single lines on the N side (`Settles`, `FillsBuy`, `FillsSell`) are the three nullable foreign keys, which DBeaver draws dashed, with a hollow diamond on the `orders` side. The table under Transformation method used lists all 15.

Earlier images (`relational_schema.jpg`, `relational_schema_v2.png`,
`relational_schema_v3.png`) were exported from pgAdmin, with a different layout
and from an older schema. They are kept only as history.

=== How to regenerate it ===

 1. Initialise the database: `./eduberza -init` (runs `schema_creation.sql` and `advanced_db.sql`, so `order_events` is included).
 2. In DBeaver, connect to the project database and expand ''Schemas → project → Tables''.
 3. Select all 11 tables → right-click → '''View Diagram''' (or create a new ER diagram and drag the tables in).
 4. Drag each table to the position of its entity set in `ERModel_v05.png`:

   {{{
            column 1          column 2        column 3        column 4
   row 1    watchlist_items   crypto          markets         market_candles
   row 2    watchlists        holdings        .               market_trades
   row 3    users             .               orders          .
   row 4    .                 transactions    order_events    .
   }}}

   Leave the empty cells (`.`) empty. They are where the relationship
   diamonds are in the ER diagram, so the foreign-key lines will run through
   the same gaps.

 5. Right-click the canvas → '''Export diagram''' → PNG, saved as `relational_diagram_v4.png` in this folder.
