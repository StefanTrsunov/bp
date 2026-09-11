= Prototype Implementation =

The prototype is a Go command-line application in
[https://github.com/StefanTrsunov/bp/tree/main/server server/] that works against the `project`
schema in PostgreSQL. It implements all seven use cases from
[https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCaseModel.md UseCaseModel]
– the rubric requires at least three – with every database access shown as real, executed SQL.
An auxiliary program in [https://github.com/StefanTrsunov/bp/tree/main/bots bots/] simulates a
live market so prices move while the prototype is running.

Build, configure, run and test instructions:
[https://github.com/StefanTrsunov/bp/blob/main/docs/P4-Prototype/BuildInstructions.md BuildInstructions].

All pages listed below, together with the screenshots of each run, are kept in the project's
GitHub repository, [https://github.com/StefanTrsunov/bp StefanTrsunov/bp], under
`docs/P4-Prototype/`.

== Implemented use-cases ==

||=Page=||=Use-case=||=Source=||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P4-Prototype/UseCase0001Implementation.md UseCase0001Implementation]||Register a new account||[https://github.com/StefanTrsunov/bp/blob/main/server/auth.go server/auth.go]||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P4-Prototype/UseCase0002Implementation.md UseCase0002Implementation]||Log in||[https://github.com/StefanTrsunov/bp/blob/main/server/auth.go server/auth.go]||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P4-Prototype/UseCase0003Implementation.md UseCase0003Implementation]||Deposit virtual funds||[https://github.com/StefanTrsunov/bp/blob/main/server/account.go server/account.go]||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P4-Prototype/UseCase0004Implementation.md UseCase0004Implementation]||Place market BUY order||[https://github.com/StefanTrsunov/bp/blob/main/server/trade.go server/trade.go]||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P4-Prototype/UseCase0005Implementation.md UseCase0005Implementation]||Place market SELL order||[https://github.com/StefanTrsunov/bp/blob/main/server/trade.go server/trade.go]||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P4-Prototype/UseCase0006Implementation.md UseCase0006Implementation]||View portfolio and history||[https://github.com/StefanTrsunov/bp/blob/main/server/portfolio.go server/portfolio.go]||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P4-Prototype/UseCase0007Implementation.md UseCase0007Implementation]||Manage watchlist||[https://github.com/StefanTrsunov/bp/blob/main/server/watchlist.go server/watchlist.go]||

Each page mirrors its P3 use-case page and adds the actual SQL emitted by the Go code plus a
screenshot of the corresponding run against the live database. The screenshots are committed
alongside the pages, in
[https://github.com/StefanTrsunov/bp/tree/main/docs/P4-Prototype/screenshots docs/P4-Prototype/screenshots/].

== What the prototype demonstrates about the database design ==

 * '''The current price is never stored as a column.''' It is always the price of the most recent
   row in `market_trades`, read through the `v_latest_prices` view. Both the user's own fills and
   the bot's simulated trades feed the same table, so there is exactly one definition of "the
   price".
 * '''Money movements are transactional.''' Buying touches five tables – `orders`, `users`,
   `holdings`, `transactions`, `market_trades` – inside one transaction. A failed balance check
   rolls the whole thing back: after a rejected purchase there is no order row, no ledger entry
   and no holding. This is verified in the failure-path tests in
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P4-Prototype/BuildInstructions.md BuildInstructions].
 * '''Constraints do real work.''' `UNIQUE (user_id, crypto_id)` on `holdings` is what makes the
   `INSERT … ON CONFLICT DO UPDATE` upsert possible, so the weighted-average entry price is
   recomputed by the database in one statement instead of by a read-modify-write in application
   code.
 * '''No identifiers are ever typed.''' Markets are listed with their prices before any choice is
   made, and everything else is selected by symbol.

== Known limitations ==

Deliberately out of scope for a first prototype, and the natural content of the later phases:

 * Only `market` orders execute. `limit` is accepted by the schema (`orders.type`) but the
   matching logic is not implemented.
 * Passwords are SHA-256 without a salt. Adequate to demonstrate that the password itself is
   never stored; not adequate for real use. A proper password hash belongs in P9 (security).
 * Money is handled as `float64` in Go while the database columns are `numeric`. All arithmetic
   that must be exact – the weighted average – is done in SQL for that reason, but the Go side
   would need a decimal type for real use.
 * There is no connection pooling configuration and no explicit isolation level; both are P8
   topics.
== AI usage ==

AI was used in this phase and is logged in full, per the course rule for P1 onward.

 * '''Phase log:'''
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCaseModelAIUsage.md UseCaseModelAIUsage.md]
   – service used, what the AI produced, and what I decided myself.
 * '''Full conversation transcript:'''
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P1-ConceptualModel/ERModelAIUsage.md ERModelAIUsage.md]
   – the same conversation produced the P1–P4 artefacts, so the complete prompt/response log is
   kept in one place. Direct links:
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P1-ConceptualModel/ERModelAIUsage.md#session-1--2026-04-21 Session 1 – 2026-04-21],
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P1-ConceptualModel/ERModelAIUsage.md#session-2--2026-08-06--2026-08-07 Session 2 – 2026-08-06/07].

'''Service:''' Claude Code (Anthropic), https://claude.com/claude-code – Claude subscription,
model Claude Opus 4.7 (1M context).

'''In short:''' the AI proposed the actor taxonomy and drafted the seven use cases with their SQL
in session 1. In session 2 the use-case model itself was '''not''' changed – the only work was
re-executing every scenario, including the failure paths, against a live PostgreSQL 16 database.

== AI usage ==

AI was used in this phase and is logged in full, per the course rule for P1 onward.

 * '''Phase log:'''
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P4-Prototype/PrototypeImplementationAIUsage.md PrototypeImplementationAIUsage.md]
   – service used, the bugs found and fixed, the test evidence, and what I decided myself.
 * '''Full conversation transcript:'''
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P1-ConceptualModel/ERModelAIUsage.md ERModelAIUsage.md]
   – the same conversation produced the P1–P4 artefacts, so the complete prompt/response log is
   kept in one place. Direct links:
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P1-ConceptualModel/ERModelAIUsage.md#session-1--2026-04-21 Session 1 – 2026-04-21],
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P1-ConceptualModel/ERModelAIUsage.md#session-2--2026-08-06--2026-08-07 Session 2 – 2026-08-06/07].

'''Service:''' Claude Code (Anthropic), https://claude.com/claude-code – Claude subscription,
model Claude Opus 4.7 (1M context).

'''In short:''' session 1 rewrote the existing Chi/HTTP backend as the CLI prototype covering
UC0001–UC0007 and added the market bot. Session 2 was a review pass I asked for, which found and
fixed three bugs – a path-resolution bug that made the documented build instructions fail, an
infinite loop at end of input, and an error check in the wrong order that misreported database
failures as "Insufficient holding" – and replaced the read-modify-write holding update with a
single `INSERT … ON CONFLICT DO UPDATE`.
