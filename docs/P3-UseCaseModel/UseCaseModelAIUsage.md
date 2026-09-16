# Use-Case Model AI Usage

## Name of AI service/solution that was used

**Claude Code** (Anthropic)

- **URL:** https://claude.com/claude-code
- **Type of service/subscription:** Claude subscription, model Claude Opus 4.7 (1M context).

## Final result

### Results in details / description

The AI:

- Proposed the actor taxonomy (Visitor, Trader, Market Simulator) from the project description and the existing Go code.
- Derived a set of 7 use cases covering the full trading loop (register, login, deposit, buy, sell, view portfolio, watchlist).
- Wrote each `UseCaseXXXX.md` file with:
  - initiating actor, other actors, goals
  - step-by-step dialog-form scenario
  - **tested** SQL statements for every database-touching step, using the `project` schema
  - alternate flows for the most common failure cases (insufficient funds, insufficient holding, duplicate user, invalid input)

## Summary of AI involvement

| | Session 1 — 2026-04-21 | Session 2 — 2026-08-06/07 |
|---|---|---|
| **What I brought** | The project description in `opis.md` and the existing Go backend | The use-case model as completed in session 1 |
| **What the AI did** | Proposed the actor taxonomy and drafted seven use cases with tested SQL | Nothing — the model was not changed |
| **What I decided** | To go solo, and therefore to document seven use cases rather than the three the rubric requires | To re-verify every scenario's SQL against a live database rather than trust the April run |

This phase was finished in session 1. In session 2 the only work was
verification: each scenario was executed against a live PostgreSQL 16 database,
including the failure paths, and the results recorded on the
`UseCaseXXXXImplementation` pages.

## Entire AI usage log

See [ERModelAIUsage](../P1-ConceptualModel/ERModelAIUsage.md) for the full transcript — the same 2026-04-21 session produced the use-case documentation. The defining student prompt was:

> I'm going solo do everything that you need to do, and tell me after what do I need to do

which led the AI to pick "solo → 3 minimum per rubric → document 7 for a margin" as a default.

> **Student action required:** append any future refinements of the use-case list or scenarios here.


### Session 2 — 2026-08-06 / 2026-08-07

No changes were made to the use-case model in this session: the actor list, the
seven use cases and the scenario SQL in `UseCase0001`–`UseCase0007` are as
produced on 2026-04-21. The SQL in those scenarios was, however, re-verified by
executing the corresponding prototype flows against a live PostgreSQL 16
database, including the failure paths (insufficient funds, insufficient holding,
duplicate registration, wrong password). The results are documented per use case
on the `UseCaseXXXXImplementation` pages.

### Session 3 — 2026-09-16

Driven by the design review logged in full in
[ERModelAIUsage](../P1-ConceptualModel/ERModelAIUsage.md#session-3--2026-09-16):
placing a sell order checked `holdings.quantity` directly, with no way to
record that part of a position was already promised to another, unsettled
order.

**What changed:**

- [UseCase0005](UseCase0005.md) — the scenario now reserves the crypto
  (`holdings.reserved_quantity`) before removing it from the position, checks
  `quantity - reserved_quantity` rather than raw `quantity`, and adds a
  worked example and a note on why the reserve and settle steps stay inside
  one transaction rather than two (only market orders are implemented, and
  splitting into two commits would risk an order stuck `open` with no cancel
  use case to recover it).
- [UseCase0004](UseCase0004.md) — no change to the balance logic, but the
  order insert now goes through `status='open'` before a final
  `UPDATE ... SET status='executed'`, matching the sell side, so `Orders`
  genuinely has the lifecycle [ERModel](../P1-ConceptualModel/ERModel.md)
  describes for it rather than a status column that is only ever written
  once.
- [UseCase0006](UseCase0006.md) — the `v_portfolio` reference and its query
  gained `reserved_quantity`/`available_quantity`, since the portfolio screen
  is where a Trader would actually see the new field.
- The use-case importance table and UC0005's one-line description in
  [UseCaseModel](UseCaseModel.md) were reworded to mention the reservation.

Every changed scenario's SQL was re-run against the live database, including a
two-concurrent-sells test that reproduces the exact bug being fixed: see
[UseCase0005Implementation](../P4-Prototype/UseCase0005Implementation.md).

**What I decided:** to keep this a revision of the existing UC0004/UC0005
pages rather than a new use case (e.g. "cancel order") — `cancelled` remains
an unused status, same as before, since nothing in the prototype produces it
and inventing a cancel flow was not what the review asked for.
