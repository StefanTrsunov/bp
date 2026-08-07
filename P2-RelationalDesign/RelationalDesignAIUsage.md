# Relational Design AI Usage

## Name of AI service/solution that was used

**Claude Code** (Anthropic)

- **URL:** https://claude.com/claude-code
- **Type of service/subscription:** Claude subscription, model Claude Opus 4.7 (1M context).

## Final result

### Diagram

The student produces `relational_schema.jpg` in DBeaver from the live `project` schema; see [RelationalDesign](RelationalDesign.md) for instructions.

### Results in details / description

The AI:

- Consolidated two inconsistent draft schemas (`server/db/db.sql` and `server/db/schema.sql`) into a single `schema_creation.sql`.
- Corrected foreign-key errors in the original (the `crypto_id` column in `holdings`, `orders`, and `transactions` had been pointed at both `users(id)` and `crypto(id)`; the AI split it into separate `user_id` and `crypto_id` columns per `ep-diagram.md`).
- Added two convenience views, `v_latest_prices` and `v_portfolio`, to keep the Go CLI simple.
- Produced a sample-data script `data_load.sql` that TRUNCATEs and re-inserts deterministic rows, so the "must work on empty DB and on a DB that already has data" requirement from P2 is met.
- Documented normalisation up to 3NF and the intentional denormalisation of `holdings.avg_price`.

## Summary of AI involvement

| | Session 1 — 2026-04-21 | Session 2 — 2026-08-06/07 |
|---|---|---|
| **What I brought** | My own draft SQL (`db.sql`, `schema.sql`) and the model in `ep-diagram.md` | The schema as it stood after session 1 |
| **What the AI did** | Reviewed my SQL, found the foreign-key errors, consolidated two inconsistent drafts into one script | Reviewed the schema again; one constraint change, plus documentation of the transformation |
| **What I decided** | Which corrections to adopt, to keep both balance columns, to drop the secret-question fields | To make `avg_price` `NOT NULL` rather than handle nulls in application code |

The relational model in this phase is a transformation of *my* ER model, and the
foreign-key errors the AI found in session 1 were errors in *my* draft SQL — that
review is the single most useful thing the AI did on this phase.

## Entire AI usage log

See [ERModelAIUsage](../P1-ConceptualModel/ERModelAIUsage.md) — the full transcript of the 2026-04-21 conversation covers both P1 and P2 work. The specific prompts that drove the relational-design output were the same "make it work and make it fill in or to follow all of the needed instructions" instruction and the student's subsequent "do everything that you need to do".

> **Student action required:** append any future consultations where you asked the AI to refine the schema, tune constraints, or write additional queries.


### Session 2 — 2026-08-06 / 2026-08-07

Prompts are logged in full in [ERModelAIUsage](../P1-ConceptualModel/ERModelAIUsage.md#session-2--2026-08-06--2026-08-07);
the one that drove this phase was *"Also fix some database things or golang
things if you think we can do it better"*. Changes to the P2 artefacts:

- `holdings.avg_price` changed from nullable to `NOT NULL DEFAULT 0 CHECK
  (avg_price >= 0)`. Reason: it feeds the P/L arithmetic in `v_portfolio`, and
  SQL arithmetic involving `NULL` produces `NULL`, so a nullable average would
  have silently blanked the unrealised-P/L column of a real position. A related
  crash path in the Go code (scanning a `NULL` average into a non-nullable
  `float64`, which was reported to the user as "Insufficient holding") was fixed
  at the same time.
- [RelationalDesign](RelationalDesign.md) gained an explicit account of the
  partial transformation: which ER construct each foreign key comes from, that
  M:N relationships with attributes become tables whose foreign-key pair is a
  `UNIQUE` constraint, and that total participation becomes `NOT NULL` — which is
  why `transactions.related_order` is the one nullable foreign key.
- The candidate keys of `holdings` and `watchlist_items` are now documented as
  the relationship keys `{user_id, crypto_id}` and `{watchlist_id, crypto_id}`.

Both scripts were re-run end to end against PostgreSQL 16 after these changes.

> **Still outstanding:** `relational_schema.jpg` must be exported from DBeaver
> against the faculty database. No AI involvement is possible there — it needs a
> live connection to your assigned database.
