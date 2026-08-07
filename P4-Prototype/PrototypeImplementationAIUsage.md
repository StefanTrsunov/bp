# Prototype Implementation AI Usage

## Name of AI service/solution that was used

**Claude Code** (Anthropic)

- **URL:** https://claude.com/claude-code
- **Type of service/subscription:** Claude subscription, model Claude Opus 4.7 (1M context).

## Final result

### Results in details / description

During the 2026-04-21 session the AI:

- Replaced the broken HTTP + frontend scaffolding (which the student had already decided to drop) with a single-binary CLI prototype in Go, split across `main.go`, `cli.go`, `auth.go`, `account.go`, `market.go`, `trade.go`, `portfolio.go`, `watchlist.go`.
- Consolidated the broken `db.go` — which used to drop every table on every startup — into a single `Connect()` plus explicit `-init` and `-load-data` flags.
- Moved `go.mod` from `server/` to the project root so the same module graph covers both `server/` and `bots/`.
- Fixed `go.mod`: removed the unused MySQL driver, promoted `github.com/lib/pq` to a direct dependency.
- Implemented the trade flows as real database transactions with row-level `FOR UPDATE` locks, cost-basis bookkeeping, and a ledger row per operation.
- Wrote a 140-line market-simulation bot that inserts trades and upserts 1-minute candles every tick.
- Exercised the full prototype end-to-end against a running PostgreSQL on port 5433 and verified a sample buy and portfolio view produced the expected numbers.

### Test evidence

```
Order executed: buy 0.0100 BTC @ 67140.000000 (notional 671.4000 USD)

  Symbol        Quantity         Avg buy         Current           Value  Unrealised P/L
  BTC             0.0100    67140.000000    67140.000000        671.4000         +0.0000
  ETH             0.5000     3500.000000     3520.000000       1760.0000        +10.0000
  TOTAL                                                        2431.4000        +10.0000

  Cash available : 7578.6000 USD
  Portfolio value: 2431.4000 USD
  Net worth      : 10010.0000 USD
```

## Summary of AI involvement

| | Session 1 — 2026-04-21 | Session 2 — 2026-08-06/07 |
|---|---|---|
| **What I brought** | My existing Go backend (Chi HTTP handlers) and a half-finished frontend | The CLI prototype as it stood after session 1 |
| **What the AI did** | Rewrote the backend as a CLI covering UC0001–UC0007, wrote the market bot | Reviewed the code, found and fixed three bugs, improved the holding upsert |
| **What I decided** | To delete the frontend, to build a CLI rather than a web app, to keep the market simulator | To ask for a code review pass rather than documentation alone |

The prototype was built in session 1 and worked. What session 2 added was a
review pass I asked for specifically because I have to defend this code in
person: it turned up a path-resolution bug that made my own documented build
instructions fail, an infinite loop at end of input, and an error check in the
wrong order that misreported database failures as "Insufficient holding".

## Entire AI usage log

See [ERModelAIUsage](../P1-ConceptualModel/ERModelAIUsage.md) for the full prompt/response transcript of the 2026-04-21 session — that single conversation produced all of the P1–P4 artefacts. The defining student prompt for P4 was:

> do everything that you need to do, and tell me after what do I need to do

which translated into the rewrite of the backend and the writing of this documentation.

> **Student action required:** append any further prompts here where you asked the AI to debug, extend, or refactor the prototype.


### Session 2 — 2026-08-06 / 2026-08-07

Prompts are logged in full in [ERModelAIUsage](../P1-ConceptualModel/ERModelAIUsage.md#session-2--2026-08-06--2026-08-07).
The student asked the AI to complete the phase documentation and to *"fix some
database things or golang things if you think we can do it better"*. What the AI
changed in the prototype, and why:

**Bugs found and fixed**

1. `server/db/db.go` resolved `../.env` and `db/schema_creation.sql` as paths
   relative to the working directory, so they only worked when the program was
   started from inside `server/`. Following the documented instructions — build
   from the repository root and run `./eduberza -init` — failed with
   `password authentication failed for user "postgres"`, because the `.env` file
   was never found and the defaults were used. The two SQL scripts are now
   compiled into the binary with `go:embed`, and `.env` is located by searching
   the working directory and every parent. Real environment variables now take
   precedence over the file, which is what allows the prototype to be pointed at
   the faculty database without editing anything.
2. `prompt()` in `server/cli.go` ignored the error from `ReadString`. At end of
   input — Ctrl-D, or a scripted run — it returned an empty string forever and
   the menu loop spun printing "Unknown option." without end. It now exits
   cleanly.
3. On the sell path, `trade.go` checked `err == sql.ErrNoRows || held < qty`
   before checking for other errors, so any scan failure was reported to the user
   as "Insufficient holding" regardless of the real cause. The error check now
   comes first.

**Improvements**

4. The holding upsert was a read-modify-write in Go (`SELECT ... FOR UPDATE`,
   compute the new weighted average in `float64`, then `INSERT` or `UPDATE`). It
   is now a single `INSERT … ON CONFLICT (user_id, crypto_id) DO UPDATE`, so the
   average is recomputed by PostgreSQL in `numeric` arithmetic and the statement
   relies on the unique constraint that the relational design already declared.
5. `TerraER3.11.jar` was removed from the repository and `.gitignore` now
   excludes `*.jar`, because P4 requires third-party executables to be
   downloaded rather than committed. `.env` is excluded too and `.env.example`
   was added in its place.
6. `image.png`, a TradingView screenshot, was deleted — the project has no
   licence to publish it and P4 requires explicit usage rights.

**Verification**

All seven use cases were executed against a live PostgreSQL 16 database. The
screenshots on the `UseCaseXXXXImplementation` pages are captures of those runs.
The four failure paths were tested, and the rollback behaviour was checked
directly in SQL: after a rejected purchase, the affected user has zero rows in
`orders`, `transactions` and `holdings`.

> **Student action required:** read the changed files (`server/db/db.go`,
> `server/cli.go`, `server/trade.go`, `server/db/schema_creation.sql`) before the
> presentation. You will be asked how the buy transaction works, and the answer
> has to be yours.
