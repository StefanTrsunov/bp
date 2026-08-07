# Prototype Implementation

The prototype is a Go command-line application in `server/` that works against
the `project` schema in PostgreSQL. It implements all seven use cases from
[UseCaseModel](../P3-UseCaseModel/UseCaseModel.md) — the rubric requires at least three — with
every database access shown as real, executed SQL. An auxiliary program in
`bots/` simulates a live market so prices move while the prototype is running.

Build, configure, run and test instructions: [BuildInstructions](BuildInstructions.md).

## Implemented use-cases

| Page | Use-case | Source |
|------|----------|--------|
| [UseCase0001Implementation](UseCase0001Implementation.md) | Register a new account | `server/auth.go` |
| [UseCase0002Implementation](UseCase0002Implementation.md) | Log in | `server/auth.go` |
| [UseCase0003Implementation](UseCase0003Implementation.md) | Deposit virtual funds | `server/account.go` |
| [UseCase0004Implementation](UseCase0004Implementation.md) | Place market BUY order | `server/trade.go` |
| [UseCase0005Implementation](UseCase0005Implementation.md) | Place market SELL order | `server/trade.go` |
| [UseCase0006Implementation](UseCase0006Implementation.md) | View portfolio and history | `server/portfolio.go` |
| [UseCase0007Implementation](UseCase0007Implementation.md) | Manage watchlist | `server/watchlist.go` |

Each page mirrors its P3 use-case page and adds the actual SQL emitted by the Go
code plus a screenshot of the corresponding run against the live database.

## What the prototype demonstrates about the database design

- **The current price is never stored as a column.** It is always the price of
  the most recent row in `market_trades`, read through the `v_latest_prices`
  view. Both the user's own fills and the bot's simulated trades feed the same
  table, so there is exactly one definition of "the price".
- **Money movements are transactional.** Buying touches five tables — `orders`,
  `users`, `holdings`, `transactions`, `market_trades` — inside one transaction.
  A failed balance check rolls the whole thing back: after a rejected purchase
  there is no order row, no ledger entry and no holding. This is verified in the
  failure-path tests in [BuildInstructions](BuildInstructions.md).
- **Constraints do real work.** `UNIQUE (user_id, crypto_id)` on `holdings` is
  what makes the `INSERT … ON CONFLICT DO UPDATE` upsert possible, so the
  weighted-average entry price is recomputed by the database in one statement
  instead of by a read-modify-write in application code.
- **No identifiers are ever typed.** Markets are listed with their prices before
  any choice is made, and everything else is selected by symbol.

## Known limitations

Deliberately out of scope for a first prototype, and the natural content of the
later phases:

- Only `market` orders execute. `limit` is accepted by the schema
  (`orders.type`) but the matching logic is not implemented.
- Passwords are SHA-256 without a salt. Adequate to demonstrate that the
  password itself is never stored; not adequate for real use. A proper
  password hash belongs in P9 (security).
- Money is handled as `float64` in Go while the database columns are `numeric`.
  All arithmetic that must be exact — the weighted average — is done in SQL for
  that reason, but the Go side would need a decimal type for real use.
- There is no connection pooling configuration and no explicit isolation level;
  both are P8 topics.
