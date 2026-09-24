= Advanced Reports AI Usage =

== Name of AI service/solution that was used ==

'''Claude Code''' (Anthropic)

 * '''URL:''' `https://claude.com/claude-code`
 * '''Type of service/subscription:''' Claude subscription, model Claude Sonnet 5.

== Final result ==

=== Diagram ===

None. Both reports read `transactions`, `market_trades`, `orders`, `markets`, `crypto` and
`users` exactly as they already existed after
Normalization — no attribute or relation was missing,
so [wiki:ERModel] and
[wiki:RelationalDesign] needed no changes and there is
no new diagram for this phase. This is stated explicitly rather than left implicit because the
phase rubric specifically calls out modifying the design as the fallback when a good report
idea can't be answered by the data on hand — it wasn't needed here.

=== Results in details / description ===

The AI:

 * Turned my two fully-specified report questions (the exact P/L, ROI, consistency, volume,
   return, volatility and participation formulas were mine) into two single-statement SQL
   queries, each wrapped as a `LANGUAGE sql STABLE` function
   (`project.report_top_traders`, `project.report_market_performance`) in
   `schema_creation.sql`, so the phase's "just one SQL
   query" requirement is met by the query text itself, while still giving the prototype a
   clean, parameterised, named thing to call.

The two functions, from `schema_creation.sql`:

{{{
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
        ROUND(ms.avg_price, 6)                                                            AS avg_price,
        ROUND((ms.last_price - ms.first_price) / NULLIF(ms.first_price, 0) * 100, 2)      AS market_return_pct,
        COALESCE(p.participating_users, 0)                                                AS participating_users
    FROM market_stats ms
    JOIN project.markets m ON m.id = ms.market_id
    JOIN project.crypto  c ON c.id = m.crypto_id
    LEFT JOIN participation p ON p.market_id = ms.market_id
    ORDER BY ms.total_volume DESC;
$$;
}}}

 * Wired both into the running CLI as real menu options — `server/reports.go`, options
   `[10]`/`[11]` in `server/cli.go` — rather than leaving them as documentation-only SQL, per
   the phase's own framing ("used as reports within your application").
 * Wrote the relational-algebra equivalent of each query, including how to express
   `FIRST_VALUE`/`LAST_VALUE` (which have no classical RA equivalent) as an aggregation for the
   boundary timestamp followed by a self-join, and how to express `FILTER (WHERE …)`-style
   conditional counts as separate groupings recombined with left outer joins.
 * Noticed that the existing `data_load.sql` seed data (a few minutes of trade history) cannot
   demonstrate either report meaningfully — everything falls into one quarter, so "consistency"
   and "market return over time" have nothing to show — and wrote
   `reports_demo_data.sql`, an optional, separate,
   idempotent script adding five quarters of synthetic transactions, market trades and executed
   orders, deliberately excluded from `-init`/`-load-data` so it cannot disturb the balances the
   other use cases' documented "verified run" sections depend on.

`reports_demo_data.sql`:

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

 * Ran both reports against a live PostgreSQL 16 database with that demo data loaded, through
   the actual CLI, and used the real output (including a run where alice's seeded quarter
   interacted with a pre-existing `data_load.sql` transaction and flipped a profitable quarter
   into a loss) as the verified evidence in [wiki:AdvancedReports], rather
   than inventing example numbers.

== Summary of AI involvement ==

||  ||= This session — 2026-09-16 =||
||= What I brought =|| The phase rubric, plus both report questions fully specified down to the exact aggregate formulas ||
||= What the AI did =|| Wrote the SQL, wrote the relational algebra, wired the reports into the CLI, designed and ran the demonstration data, verified everything against a live database ||
||= What I decided =|| To keep both reports as SQL functions rather than plain ad-hoc queries so they are actually usable from the application; to accept the AI's synthetic multi-quarter demo dataset rather than wait for enough real usage history to accumulate ||

The two ideas and their formulas were mine, specified in enough detail (P/L as the sum of
buy+sell+fee transactions, ROI relative to total buys, consistency as a share of profitable
quarters, market return as first-vs-last trade price, volatility as price standard deviation,
participation from orders rather than trades) that there was no separate "AI alternative
idea" to borrow from and document a change against, unlike the more open-ended P1–P3 phases —
the AI's job here was implementation and verification of a fully-specified design, which is
what is logged above and in the prompt below.

== Entire AI usage log ==

=== 2026-09-16 ===

'''Intent:''' hand over the P6 rubric together with both report ideas, fully specified, and
have the whole phase — SQL, relational algebra, prototype integration, and demonstration data
— produced and verified in one pass.

'''Prompt (student, verbatim):'''
> Phase P6: Complex DB Reports (SQL, Stored Procedures, Relational Algebra)
> [the full phase rubric was pasted: 2 complex analytical reports solvable each with one SQL
> query, usable as reports within the application, with a note that helper views/functions/
> procedures are acceptable when pure SQL isn't enough, that the design should be extended if
> a good idea needs data that doesn't exist yet, a requirement for the corresponding relational
> algebra, the exact `AdvancedReports`/`AdvancedReportsAIUsage` wiki templates, and the phase's
> AI-use rules]
>
> I will describe for you the 2 more complex sql queries:
> 1. Find the users who performed the best in a selected quarter, year, or multi-year period
>    based on their realized trading performance, and show their total profit/loss, total
>    amount invested, ROI, number of profitable and losing periods, and consistency of
>    returns. Calculate realized P/L as SUM(sell transactions + buy transactions + fee
>    transactions), calculate ROI as realized P/L / absolute value of total buy transactions ×
>    100, and calculate consistency as profitable periods / total periods × 100.
> 2. Find which cryptocurrency markets performed best during a selected quarter, year, or
>    multi-year period based on trading activity and price behavior, and report the markets
>    with the highest trading volume, number of trades, number of participating users, and
>    price return. Calculate total volume as SUM(trade quantity), average trading price as
>    AVG(price), market return as (last trade price − first trade price) / first trade price ×
>    100, price volatility as standard deviation of trade prices, and user participation as
>    COUNT(DISTINCT user_id) from the related executed orders.

'''Response (AI, summarised):'''
 * Confirmed both report questions were answerable from the existing schema with no new
   columns or tables, and said so explicitly rather than silently skipping that check.
 * Wrote `report_top_traders` and `report_market_performance` as SQL functions, added to
   `schema_creation.sql` under a new `REPORTS (P6)` section.
 * Wrote `server/reports.go` (`ShowTopTraders`, `ShowMarketPerformance`, a shared
   `promptPeriod` helper) and added menu options `[10]`/`[11]` to `server/cli.go`.
 * Wrote `server/db/reports_demo_data.sql` for a richer, multi-quarter demonstration, and
   documented in its own header exactly why it is optional and what it deliberately does not
   touch (user balances, holdings).
 * Built the prototype, ran both reports against the live database with the demo data loaded,
   cross-checked the SQL output against hand-computed expected values for both seeded users,
   and used that real output as the verified evidence.
 * Wrote out the relational-algebra derivation for each query and [wiki:AdvancedReports].

'''What I decided:''' to keep the demo dataset out of `-init`/`-load-data` rather than merge it
into `data_load.sql`, since the other phases' documented expected values (specific balances in
[wiki:BuildInstructions]) depend on the seed data staying
exactly as it is.

> '''Student action required.''' Read [wiki:AdvancedReports] end to end
> before the defense, and be ready to compute one period's realized P/L or one market's return
> by hand from the raw `transactions`/`market_trades` rows — the numbers in the verified run
> are real output, not invented, so they can be checked against
> `reports_demo_data.sql` (shown above) directly. Append any further
> prompts here if you ask for revisions.

=== Follow-up — 2026-09-17 ===

'''Intent:''' simplify the market performance report after seeing it run — with only a handful
of trades per market in most periods, price volatility read as noise rather than a useful
signal.

'''Prompt (student, verbatim):'''
> Can you tell me the exact database_url so I can execute the schema creating and the data_load?
>
> From the Market Performance can we remove Volatility, I don't think that is that useful, also
> can you tell me what is users column?

'''Response (AI, summarised):'''
 * Gave the local dev connection string (`postgresql://bp_project:1234@localhost:5433/bp_database`,
   from `.env`) and explained `participating_users` is `COUNT(DISTINCT user_id)` from that
   market's executed orders, not from `market_trades` (which has no `user_id`).
 * Removed `price_volatility`/`STDDEV(price)` from `report_market_performance()` in
   `schema_creation.sql`, from its `RETURNS TABLE` and its `SELECT`, and from the corresponding
   column in `server/reports.go`'s `ShowMarketPerformance`.
 * Updated the relational algebra (`Stats`, `Result`) and the SQL listing, verified run output,
   and prose in [wiki:AdvancedReports] to match, and added a short note
   explaining why the column was dropped.
 * Rebuilt, re-ran `-init` and `reports_demo_data.sql` against the live database, and
   re-verified the market performance report through the actual CLI before and after the
   change to confirm only the one column disappeared and every other number is unchanged.

'''What I decided:''' to drop the column entirely rather than keep it computed-but-hidden,
since an unused computation left in the query is exactly the kind of thing that should not
survive a review.
