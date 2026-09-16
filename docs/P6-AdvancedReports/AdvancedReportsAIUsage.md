# Advanced Reports AI Usage

## Name of AI service/solution that was used

**Claude Code** (Anthropic)

- **URL:** https://claude.com/claude-code
- **Type of service/subscription:** Claude subscription, model Claude Sonnet 5.

## Final result

### Diagram

None. Both reports read `transactions`, `market_trades`, `orders`, `markets`, `crypto` and
`users` exactly as they already existed after
[Normalization](../P5-Normalization/Normalization.md) — no attribute or relation was missing,
so [ERModel](../P1-ConceptualModel/ERModel.md) and
[RelationalDesign](../P2-RelationalDesign/RelationalDesign.md) needed no changes and there is
no new diagram for this phase. This is stated explicitly rather than left implicit because the
phase rubric specifically calls out modifying the design as the fallback when a good report
idea can't be answered by the data on hand — it wasn't needed here.

### Results in details / description

The AI:

- Turned my two fully-specified report questions (the exact P/L, ROI, consistency, volume,
  return, volatility and participation formulas were mine) into two single-statement SQL
  queries, each wrapped as a `LANGUAGE sql STABLE` function
  (`project.report_top_traders`, `project.report_market_performance`) in
  [`schema_creation.sql`](../../server/db/schema_creation.sql), so the phase's "just one SQL
  query" requirement is met by the query text itself, while still giving the prototype a
  clean, parameterised, named thing to call.
- Wired both into the running CLI as real menu options — `server/reports.go`, options
  `[10]`/`[11]` in `server/cli.go` — rather than leaving them as documentation-only SQL, per
  the phase's own framing ("used as reports within your application").
- Wrote the relational-algebra equivalent of each query, including how to express
  `FIRST_VALUE`/`LAST_VALUE` (which have no classical RA equivalent) as an aggregation for the
  boundary timestamp followed by a self-join, and how to express `FILTER (WHERE …)`-style
  conditional counts as separate groupings recombined with left outer joins.
- Noticed that the existing `data_load.sql` seed data (a few minutes of trade history) cannot
  demonstrate either report meaningfully — everything falls into one quarter, so "consistency"
  and "market return over time" have nothing to show — and wrote
  [`reports_demo_data.sql`](../../server/db/reports_demo_data.sql), an optional, separate,
  idempotent script adding five quarters of synthetic transactions, market trades and executed
  orders, deliberately excluded from `-init`/`-load-data` so it cannot disturb the balances the
  other use cases' documented "verified run" sections depend on.
- Ran both reports against a live PostgreSQL 16 database with that demo data loaded, through
  the actual CLI, and used the real output (including a run where alice's seeded quarter
  interacted with a pre-existing `data_load.sql` transaction and flipped a profitable quarter
  into a loss) as the verified evidence in [AdvancedReports.md](AdvancedReports.md), rather
  than inventing example numbers.

## Summary of AI involvement

| | This session — 2026-09-16 |
|---|---|
| **What I brought** | The phase rubric, plus both report questions fully specified down to the exact aggregate formulas |
| **What the AI did** | Wrote the SQL, wrote the relational algebra, wired the reports into the CLI, designed and ran the demonstration data, verified everything against a live database |
| **What I decided** | To keep both reports as SQL functions rather than plain ad-hoc queries so they are actually usable from the application; to accept the AI's synthetic multi-quarter demo dataset rather than wait for enough real usage history to accumulate |

The two ideas and their formulas were mine, specified in enough detail (P/L as the sum of
buy+sell+fee transactions, ROI relative to total buys, consistency as a share of profitable
quarters, market return as first-vs-last trade price, volatility as price standard deviation,
participation from orders rather than trades) that there was no separate "AI alternative
idea" to borrow from and document a change against, unlike the more open-ended P1–P3 phases —
the AI's job here was implementation and verification of a fully-specified design, which is
what is logged above and in the prompt below.

## Entire AI usage log

### 2026-09-16

**Intent:** hand over the P6 rubric together with both report ideas, fully specified, and
have the whole phase — SQL, relational algebra, prototype integration, and demonstration data
— produced and verified in one pass.

**Prompt (student, verbatim):**
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

**Response (AI, summarised):**
- Confirmed both report questions were answerable from the existing schema with no new
  columns or tables, and said so explicitly rather than silently skipping that check.
- Wrote `report_top_traders` and `report_market_performance` as SQL functions, added to
  `schema_creation.sql` under a new `REPORTS (P6)` section.
- Wrote `server/reports.go` (`ShowTopTraders`, `ShowMarketPerformance`, a shared
  `promptPeriod` helper) and added menu options `[10]`/`[11]` to `server/cli.go`.
- Wrote `server/db/reports_demo_data.sql` for a richer, multi-quarter demonstration, and
  documented in its own header exactly why it is optional and what it deliberately does not
  touch (user balances, holdings).
- Built the prototype, ran both reports against the live database with the demo data loaded,
  cross-checked the SQL output against hand-computed expected values for both seeded users,
  and used that real output as the verified evidence.
- Wrote out the relational-algebra derivation for each query and [AdvancedReports.md](AdvancedReports.md).

**What I decided:** to keep the demo dataset out of `-init`/`-load-data` rather than merge it
into `data_load.sql`, since the other phases' documented expected values (specific balances in
[BuildInstructions](../P4-Prototype/BuildInstructions.md)) depend on the seed data staying
exactly as it is.

> **Student action required.** Read [AdvancedReports.md](AdvancedReports.md) end to end
> before the defense, and be ready to compute one period's realized P/L or one market's return
> by hand from the raw `transactions`/`market_trades` rows — the numbers in the verified run
> are real output, not invented, so they can be checked against
> [`reports_demo_data.sql`](../../server/db/reports_demo_data.sql) directly. Append any further
> prompts here if you ask for revisions.
