= Advanced Reports =

This is a solo project (see [wiki:UseCaseModel]),
so the rubric's "2 per team member" is 2 reports total. Both are implemented as
single SQL statements, wrapped as callable SQL functions in
`schema_creation.sql` (`report_top_traders`,
`report_market_performance`) so they are actual reports inside the prototype — menu
options `[10]` and `[11]` in `server/reports.go` — not just documentation. No change to
[wiki:ERModel] or [wiki:RelationalDesign]
was needed: both reports read `transactions`, `market_trades` and `orders`, all of which
already carry everything required.

=== Notation used below ===

Both solutions need grouping, aggregation and computed attributes that plain relational
algebra has no notation for, so the relational-algebra sections use the standard ''extended''
operators:

||= Symbol =||= Meaning =||
|| `σ_cond(R)` || selection ||
|| `π_list(R)` || projection — a list entry `expr → name` is a '''generalized projection''': a computed attribute, not just a column reference ||
|| `ρ_name(R)` || rename ||
|| `R ⋈_cond S` || inner join ||
|| `R ⟕_cond S` || left outer join (needed wherever a group can legitimately have zero matching rows on the other side, e.g. zero profitable periods, zero participating users) ||
|| `γ_{grouping; agg → name, …}(R)` || grouping/aggregation ||
|| `τ_attr(R)` || sort, for the presentation order only ||

== Top traders by realized performance ==

=== Data requirements description ===

''"Which users actually made money, how much, how efficiently, and how consistently — over
a quarter, a year, or several years?"'' This is the natural crypto-exchange analogue of "which
customers bring the most profit" from the phase brief: a Trader's `available_balance` and
`invested_balance` (P1 `Users`) show a live snapshot, but they say nothing about performance
''over a chosen window'', and nothing at all about whether a user's results are one lucky
quarter or a repeatable pattern. All of it is derivable from
`transactions` (defined in `schema_creation.sql`) as it already exists: every buy, sell
and fee is one signed row there (see [wiki:UseCase0004] and
[wiki:UseCase0005] for how each row is produced), so no new
column or table is needed.

The `transactions` table, from `schema_creation.sql`:

{{{
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
}}}

Given a period `[from, to)`:

 * '''Realized P/L''' = `SUM(amount)` over that user's `buy`, `sell` and `fee` transactions in
   the period (deposits excluded — they are not trading results).
 * '''Total invested''' = absolute value of the sum of that user's `buy` transactions in the
   period (buy amounts are stored negative, per
   [wiki:ERModel]).
 * '''ROI %''' = realized P/L ÷ total invested × 100.
 * The period is additionally bucketed into '''quarters''' internally, regardless of how wide
   `[from, to)` is, to measure:
   * '''Profitable / losing periods''' — how many quarters inside the window had positive vs.
     negative P/L.
   * '''Consistency %''' = profitable periods ÷ total periods with any activity × 100 — two
     users can have the same total P/L with very different risk profiles, and this is the
     number that tells them apart.

=== Solution SQL ===

Implemented as `project.report_top_traders(p_from, p_to)` in
`schema_creation.sql`:

{{{
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
}}}

One `SELECT`, one `WITH` CTE — the CTE does the quarter bucketing per user, the outer query
rolls those buckets up into the totals, the ROI/consistency percentages and the ranking.

'''Verified run.''' `reports_demo_data.sql` adds five
quarters of round-trip trades (2025-07 through 2026-07) on top of the normal seed data
specifically so this report has more than one period to work with — see that file's header
(shown in full in the Demonstration data section below)
for exactly what it inserts and why it is optional rather than part of `-init`. Run against
PostgreSQL 16 with `data_load.sql` + `reports_demo_data.sql` loaded, through the actual CLI
(`[10] Report: top traders`, range `2025-01-01` to `2026-09-17`):

{{{
  Username      Realized P/L        Invested       ROI %   Prof.    Loss   Total  Consist. %
  ------------------------------------------------------------------------------------------
  bob              +991.0000       6300.0000       15.73       3       0       3      100.00
  alice            -475.0000      24250.0000       -1.96       2       3       5       40.00
}}}

Sorting by raw P/L alone would rank alice above bob if alice's numbers were all positive; here
it does the opposite, and that is the point of the report — alice traded a much larger total
(and one of her seeded round trips landed in the same quarter as the ETH buy already in
`data_load.sql`, tipping that quarter into a loss), while bob's three quarters were smaller
but every one of them profitable, giving him both the better ROI and a perfect consistency
score. A single "total profit" column would have hidden that difference completely.

=== Solution Relational Algebra ===

{{{
T_period  = σ_{type ∈ {buy,sell,fee} ∧ created_at ≥ from ∧ created_at < to} (Transactions)

T_tagged  = π_{user_id, created_at, amount,
               (type = 'buy' ? amount : 0) → buy_amt} (T_period)

Periods   = γ_{user_id, quarter(created_at) → period ;
               SUM(amount) → period_pl, SUM(buy_amt) → period_buy} (T_tagged)

Totals      = γ_{user_id ; SUM(period_pl) → realized_pl,
                 ABS(SUM(period_buy)) → total_invested,
                 COUNT(*) → total_periods} (Periods)
Profitable  = γ_{user_id ; COUNT(*) → profitable_periods} (σ_{period_pl > 0} (Periods))
Losing      = γ_{user_id ; COUNT(*) → losing_periods}     (σ_{period_pl < 0} (Periods))

Combined  = (Totals ⟕_{user_id} Profitable) ⟕_{user_id} Losing

Ranked    = π_{user_id, realized_pl, total_invested,
               (realized_pl / total_invested × 100) → roi_pct,
               COALESCE(profitable_periods, 0) → profitable_periods,
               COALESCE(losing_periods, 0) → losing_periods,
               total_periods,
               (COALESCE(profitable_periods, 0) / total_periods × 100) → consistency_pct}
             (Combined)

Result    = τ_{realized_pl ↓} (π_{username, realized_pl, total_invested, roi_pct,
               profitable_periods, losing_periods, total_periods, consistency_pct}
               (Ranked ⋈_{user_id = id} Users))
}}}

`Totals`/`Profitable`/`Losing` are three separate groupings of the same `Periods` relation
because plain aggregation has no built-in "count only where X" operator; the two outer joins
recombine them (`⟕`, not `⋈`, because a user with zero losing quarters must still appear with
`losing_periods = 0`, not disappear from the result).

== Market performance leaderboard ==

=== Data requirements description ===

''"Which markets were actually worth making — high volume, real price movement, real user
interest — over a chosen period?"'' This is the "products that bring the most profit" /
"good locations" family of question from the phase brief, translated to markets instead of
physical products: a market with heavy volume but a dead price, or a big price swing nobody
actually traded, are both misleading on their own; this report puts volume, trade count,
price return and user participation side by side so a market's performance over a
quarter/year/multi-year window can be judged as a whole, not from one number in isolation.
Everything needed already exists: `market_trades` is the single source of truth for price and
volume for every market ([wiki:PrototypeImplementation]),
and `orders` is the only place a specific user is tied to a specific market
([wiki:ERModel]) —
`market_trades` deliberately has no `user_id` column, since it also records the market
simulator's own fills.

Given a period `[from, to)`, per market:

 * '''Total volume''' = `SUM(quantity)` over its trades in the period.
 * '''Trade count''' = `COUNT(*)` over the same trades (real fills and simulated fills alike —
   this is activity, not just user activity).
 * '''Average trading price''' = `AVG(price)` over the same trades.
 * '''Market return %''' = `(last trade price − first trade price) ÷ first trade price × 100`,
   ordering trades by `executed_at` inside the period.
 * '''Participating users''' = `COUNT(DISTINCT user_id)` from that market's '''executed orders'''
   in the period — the only correct source, since `market_trades` cannot answer this question
   at all.

=== Solution SQL ===

Implemented as `project.report_market_performance(p_from, p_to)` in
`schema_creation.sql`:

{{{
CREATE OR REPLACE FUNCTION project.report_market_performance(p_from timestamptz, p_to timestamptz)
RETURNS TABLE (
    symbol               varchar,
    quote_currency       char(3),
    total_volume         numeric,
    trade_count          bigint,
    avg_price            numeric,
    market_return_pct    numeric,
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
        ROUND(ms.avg_price, 6)                                                       AS avg_price,
        ROUND((ms.last_price - ms.first_price) / NULLIF(ms.first_price, 0) * 100, 2) AS market_return_pct,
        COALESCE(p.participating_users, 0)                                          AS participating_users
    FROM market_stats ms
    JOIN project.markets m ON m.id = ms.market_id
    JOIN project.crypto  c ON c.id = m.crypto_id
    LEFT JOIN participation p ON p.market_id = ms.market_id
    ORDER BY ms.total_volume DESC;
$$;
}}}

`FIRST_VALUE`/`LAST_VALUE` pick the period's opening and closing price per market without a
self-join; `LEFT JOIN participation` is required, not optional — a market can have trades
from the simulator alone and legitimately zero participating users, and it must still show
`0`, not disappear from the report.

'''Verified run.''' Same seed as above (`data_load.sql` + `reports_demo_data.sql`, which also
adds a BTC/USD uptrend and an ETH/USD downtrend across the same five quarters — see that
file in the Demonstration data section below). Run through the CLI (`[11] Report: market performance`, `2025-01-01` to `2026-09-17`):

{{{
  Symbol  Quote        Volume    Trades       Avg Price      Return %     Users
  -----------------------------------------------------------------------------
  DOGE    USD      29500.0000         3        0.120583         +2.95         0
  ADA     USD       2500.0000         3        0.450750         +1.62         0
  SOL     USD         23.5000         3      165.283333         +1.13         0
  ETH     USD         14.3500         8     3622.312500        -12.00         2
  BTC     USD          3.9750         9    59447.400000        +67.85         2
}}}

BTC/USD and ETH/USD are the only two markets with historical (multi-quarter) data seeded, and
they show it: BTC's price nearly tripled over the period (`+67.85%`), while ETH quietly lost
`12%`. ADA/SOL/DOGE only have the few minutes of `data_load.sql`'s own recent seed trades, so
their return numbers reflect that narrow window, and their `0` participating users is correct
— `data_load.sql` seeds trade history for every market but only ever places an ''order'' on ETH.

A price-volatility column (standard deviation of trade price) was dropped from this report
after review — with only a handful of trades per market in most periods it read as noise
rather than signal, and total volume plus return already carry the useful information.

=== Solution Relational Algebra ===

{{{
MT_period  = σ_{executed_at ≥ from ∧ executed_at < to} (MarketTrades)

Bounds     = γ_{market_id ; MIN(executed_at) → t_first, MAX(executed_at) → t_last} (MT_period)

FirstPx    = π_{market_id, price → first_price}
               (MT_period ⋈_{MT_period.market_id = Bounds.market_id
                              ∧ executed_at = t_first} Bounds)
LastPx     = π_{market_id, price → last_price}
               (MT_period ⋈_{MT_period.market_id = Bounds.market_id
                              ∧ executed_at = t_last} Bounds)

Stats      = γ_{market_id ; SUM(quantity) → total_volume, COUNT(*) → trade_count,
                AVG(price) → avg_price} (MT_period)

MarketStats = (Stats ⋈_{market_id} FirstPx) ⋈_{market_id} LastPx

O_period      = σ_{status = 'executed' ∧ executed_at ≥ from ∧ executed_at < to} (Orders)
Participation = γ_{market_id ; COUNT_DISTINCT(user_id) → participating_users} (O_period)

Joined = ((MarketStats ⟕_{market_id} Participation)
            ⋈_{market_id = id} Markets) ⋈_{crypto_id = id} Crypto

Result = τ_{total_volume ↓} (
           π_{symbol, quote_currency, total_volume, trade_count, avg_price,
              (last_price − first_price) / first_price × 100 → market_return_pct,
              COALESCE(participating_users, 0) → participating_users}
             (Joined) )
}}}

`FirstPx`/`LastPx` express `FIRST_VALUE`/`LAST_VALUE` — which have no classical relational-
algebra equivalent — as an aggregation for the boundary timestamp per market followed by a
self-join back to `MarketTrades` to recover the price at that timestamp; this is the standard
way to express "value at the extreme of a group" in extended relational algebra.

== Demonstration data ==

`reports_demo_data.sql`, the optional script both verified runs above were produced with:

{{{
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

SET search_path TO project, public;

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
INSERT INTO orders (id, user_id, market_id, side, type, status, quantity, price, placed_at, executed_at) VALUES
    ('e1111111-1111-1111-1111-111111111111', 'b1111111-1111-1111-1111-111111111111',
     'a1111111-1111-1111-1111-111111111111', 'buy', 'market', 'executed', 0.5000, 40000.000000,
     '2025-07-15 10:00', '2025-07-15 10:00'),
    ('e2222222-2222-2222-2222-222222222222', 'b1111111-1111-1111-1111-111111111111',
     'a2222222-2222-2222-2222-222222222222', 'sell', 'market', 'executed', 3.0000, 4000.000000,
     '2025-10-15 10:00', '2025-10-15 10:00'),
    ('e3333333-3333-3333-3333-333333333333', 'b2222222-2222-2222-2222-222222222222',
     'a1111111-1111-1111-1111-111111111111', 'buy', 'market', 'executed', 1.2000, 55000.000000,
     '2026-01-15 10:00', '2026-01-15 10:00'),
    ('e4444444-4444-4444-4444-444444444444', 'b2222222-2222-2222-2222-222222222222',
     'a1111111-1111-1111-1111-111111111111', 'buy', 'market', 'executed', 1.0000, 60000.000000,
     '2026-04-15 10:00', '2026-04-15 10:00'),
    ('e5555555-5555-5555-5555-555555555555', 'b3333333-3333-3333-3333-333333333333',
     'a2222222-2222-2222-2222-222222222222', 'sell', 'market', 'executed', 2.0000, 3600.000000,
     '2026-01-15 10:00', '2026-01-15 10:00');
}}}

== AI usage ==

AI was used in this phase and is logged in full, per the course rule for P1 onward.

 * '''Phase log:''' [wiki:AdvancedReportsAIUsage] — service used, what
   the AI produced, and what I decided myself.

'''Service:''' Claude Code (Anthropic), `https://claude.com/claude-code` — Claude subscription,
model Claude Sonnet 5.

'''In short:''' I specified both report questions in full — including the exact formulas for
P/L, ROI, consistency, market return, volatility and user participation — and asked the AI to
turn them into working SQL, wire them into the prototype as real reports, build the
relational-algebra equivalents, and produce demonstration data rich enough to show the
reports doing something non-trivial. In a follow-up, I asked for the price-volatility column
to be dropped from the market performance report — see the "Follow-up — 2026-09-17" section of
[wiki:AdvancedReportsAIUsage] for that change.
