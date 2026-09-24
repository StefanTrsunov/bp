# Advanced Database Development AI Usage

## Name of AI service/solution that was used

**Claude Code** (Anthropic)

- **URL:** https://claude.com/claude-code
- **Type of service/subscription:** Claude subscription, model Claude Opus 5.5.

## Final result

### Diagram

No new diagram. The data model gains four columns and one table, all listed under "Changes to
earlier phases" in [AdvancedDatabaseDevelopment](AdvancedDatabaseDevelopment.md):

- `users.reserved_balance`;
- `orders.filled_quantity` (with the status `partially_filled`);
- `market_trades.buy_order_id` and `market_trades.sell_order_id`;
- `order_events`.

The optional link from a trade to the orders it filled is a new relationship, which
[ERModel](../P1-ConceptualModel/ERModel.md) and
[RelationalDesign](../P2-RelationalDesign/RelationalDesign.md) must show as well.

### Results in details / description

My requirements, given to the AI as a list:

- complex order consistency: no invalid state changes, filled and remaining quantities
  consistent, finished orders never processed again;
- balance and order consistency: active orders consistent with reserved money and assets, no
  inconsistent balance states from order operations;
- trade consistency: trades only between valid compatible orders, never more than the remaining
  quantity, orders, trades and balances kept consistent;
- which kinds of triggers, procedures, functions and views to build;
- a background job only if it is genuinely relevant;
- basic column constraints kept out of P7.

The AI:

- Checked the existing schema against those requirements. It found that three of them could not
  be expressed without small additions: there was no filled quantity, no place for reserved
  cash, and no link from a trade to its orders. It added only the four columns listed above and
  the event table.
- For every feature, wrote down the business rule, why it is non-trivial, which PostgreSQL
  feature implements it and which tables it affects. This is the structure I asked for, and
  [AdvancedDatabaseDevelopment](AdvancedDatabaseDevelopment.md) follows it.
- Implemented [`advanced_db.sql`](../../server/db/advanced_db.sql):
  - 5 row triggers (order lifecycle, order events, trade validation, trade fill, trade
    immutability);
  - 3 deferred constraint triggers (reserved cash, reserved crypto, cash equals ledger);
  - the functions `place_order`, `match_order`, `execute_trade`, `cancel_order`,
    `order_reservation` and `latest_price`;
  - 4 views;
  - the background job `fill_marketable_orders`.
- Checked the faculty server before choosing how to schedule the background job. There is no
  `pg_cron` and the role is not a superuser, so the job is a function that the bot process calls
  after every round of price ticks.
- Adapted the two data scripts to the new consistency rules and verified that both P6 report
  outputs stay exactly as documented.
- Wrote [`advanced_db_tests.sql`](../../server/db/advanced_db_tests.sql): a trading story with 41
  checks, rolled back at the end. It ran them until all passed. The one failure along the way was
  in the test itself: a check read the data in the same statement as the job it was checking.
- Wired the prototype to use the new functions:
  - order placement is a single `place_order` call, with market or limit orders;
  - the order book, open orders and cancel are available from the menu, with cancel picked from
    a numbered list;
  - the balance screen shows reserved cash;
  - the bot runs the job.

  All of this was verified through the CLI and with the bot running.
- Wrote this documentation.

## Summary of AI involvement

| | This session — 2026-09-24 |
|---|---|
| **What I brought** | The P7 requirements for EduBerza: order, balance and trade consistency, the kinds of triggers, procedures and views, and the condition on the background job |
| **What the AI did** | Turned the requirements into concrete rules on the existing schema, implemented and tested them, wired them into the prototype, wrote the documentation |
| **What I decided** | The requirements themselves; to discard the AI's earlier, self-proposed P7 version (see the log) and redo the phase from my requirements; to keep the schema changes minimal |

## Entire AI usage log

### 2026-09-24 — earlier attempt, discarded

Earlier in the same session I had pasted the P7 and P8 rubrics without ideas of my own, and the
AI proposed and implemented a P7 of its own design: custom domains, an append-only ledger,
candles derived from trades and a maintenance job. Before submitting anything I decided to redo
the phase from my own requirements, and asked for that version to be reverted. None of it
remains in the project. It is mentioned here only so the log is complete.

### 2026-09-24 — this phase

**Prompt (student, verbatim):**
> P7 requirements are:
>
> more complex data constraints and consistency requirements
> business scenarios that require special database checks
> triggers
> stored procedures and functions
> views
> background jobs
> documentation of the implementation
>
> Basic column constraints such as NOT NULL, UNIQUE, CHECK, PRIMARY KEY, and basic foreign keys
> are Phase P2 and must NOT be proposed as P7 features.
>
> Based on my existing EduBerza database, identify and implement only genuinely NON-TRIVIAL P7
> requirements.
>
> Focus on these types of requirements:
>
> Complex order consistency
> Prevent invalid order state changes.
> Ensure filled/remaining quantities stay consistent.
> Prevent cancelled or completed orders from being processed again.
> Balance and order consistency
> Ensure active orders are consistent with reserved virtual money/assets.
> Prevent inconsistent balance states caused by order operations.
> Trade consistency
> Ensure a trade can only happen between valid compatible orders.
> Ensure trade quantity cannot exceed the remaining order quantity.
> Keep orders, trades, and balances consistent.
> Triggers
> Create triggers only for automatic database behavior that is genuinely required, such as:
> automatic validation of complex business rules
> automatic order status changes
> automatic recording of important order/trade events
> Stored procedures/functions
> Create procedures/functions for complex database operations such as:
> placing an order with the necessary consistency checks
> executing a trade while updating all related data consistently
> Views
> Create useful views for derived application data, such as:
> current order book
> active orders
> trader portfolio/balances
> order/trade history
>
> Do not recreate reports that were already implemented in P6 unless a view is needed
> specifically as part of P7.
>
> Background jobs
> Implement a meaningful background database job only if it is relevant to the existing
> EduBerza design.
> Do not create an artificial background job just to satisfy the requirement.
>
> For every proposed P7 feature, explain:
>
> the business rule
> why it is non-trivial
> which PostgreSQL feature should implement it
> which existing tables it affects
>
> Then implement the selected P7 features in the existing project without redesigning the
> database unnecessarily.
>
> Finally, document:
>
> complex data requirements
> triggers
> stored procedures/functions
> views
> background jobs
> how each one maintains consistency or enforces a business rule
> examples/tests proving that the rules work
>
> Keep the implementation strictly within P7.

(The first time I sent it the message was interrupted; I sent it again, followed by "and revert
the previous changes".)

**Response (AI, summarised):**

- **Revert.** It restored every file changed by the discarded attempt to the last commit and
  deleted the files that attempt had created. It kept the SSH connection support (from before
  P7) and my own uncommitted edits.
- **Analysis.** It reported that three requirements need data the schema doesn't have — a filled
  quantity, a reserved cash balance, and trade-to-order links — and added exactly those
  (`orders.filled_quantity` plus status `partially_filled`, `users.reserved_balance`,
  `market_trades.buy_order_id`/`sell_order_id`), plus `order_events` for the automatic event
  recording.
- **Design:**
  - A trade is always a `market_trades` row naming the orders it fills. Triggers on that table
    validate compatibility and fill the orders; the order's status is derived from its filled
    quantity by the order trigger.
  - `filled_quantity` may only change while a trade is being recorded, which is detected through
    a transaction-local setting.
  - The three balance rules are deferred constraint triggers, because every legitimate operation
    breaks them between its statements.
  - Placing an order reserves first, then matches against the order book (price–time priority),
    then fills the marketable remainder from the simulated market.
  - Rounding of reservations is defined once (`order_reservation`), so placing, filling,
    cancelling and checking always agree.
- **Background job.** It argued the job is relevant rather than artificial: the market price is
  moved by the simulator, and without the job resting limit orders would never fill once the
  price reaches them. It explained why a trigger on the bot's price ticks would be the wrong
  place for this work.
- **Verification** (local PostgreSQL 17 in Docker only, never the faculty database):
  - both P6 reports return the documented numbers;
  - the P6 demo script can be re-run without doubling anything;
  - the test story passes 41 of 41;
  - through the CLI: a limit sell resting in the book, a crossing limit buy trading at the resting
    price with the difference refunded, a market buy filled partly from the book and partly from
    the market, the order book, open orders, and cancelling with the reservation released;
  - with the bot running, the job filled a resting limit order once the price walk reached it.
- **Documentation.** It wrote [AdvancedDatabaseDevelopment](AdvancedDatabaseDevelopment.md) and
  this log, with the SQL on the page taken automatically from `advanced_db.sql` so the two cannot
  differ, together with the faculty-site (wiki) versions of both pages.

**What I decided:** the requirements are mine. I kept the AI's minimal schema additions and its
design for fulfilling them, and asked for no changes to it before it was implemented.
