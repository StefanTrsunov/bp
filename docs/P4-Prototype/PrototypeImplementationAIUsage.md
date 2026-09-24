# Prototype Implementation AI Usage

## Name of AI service/solution that was used

**Claude Code** (Anthropic), an AI coding assistant that runs in the terminal and reads and
edits the project files.

- **URL:** https://claude.com/claude-code
- **Type of service/subscription:** Claude subscription (Claude Code CLI). A different model was
  used in each session:

| Session | Date | Model |
|---------|------|-------|
| 1 | 2026-04-21 | Claude Opus 4.7 (1M context) |
| 2 | 2026-08-06 / 2026-08-07 | Claude Opus 5 (1M context) |
| 3 | 2026-09-16 | Claude Sonnet 5 |
| 4 | 2026-09-24 | Claude Opus 5.5 (1M context) |

The same sessions also worked on other phases. This page covers only what concerns the P4
prototype and its documentation.

## Final result

### Results in details / description

**My own starting code (before any AI was used).** Before session 1 I had written:

- a Go backend with HTTP handlers (Chi router);
- a draft database schema (`server/db/db.sql`, `server/db/schema.sql`) and a diagram description
  (`docs/dbdiagram.md`), based on my data model in `ep-diagram.md`;
- a `main.go` / `db.go` that connected to PostgreSQL and dropped and recreated every table on
  each start;
- a half-finished frontend, which I deleted myself at the start of session 1 because the
  prototype does not need it.

This code is older than the git repository. The first commit (2026-08-07) was made after
sessions 1 and 2, so the history in git starts from the AI-improved version. My original files
are not in the repository. What they contained, and which errors the AI found in them, is
recorded in the session 1 log below and in [ERModelAIUsage](../P1-ConceptualModel/ERModelAIUsage.md).

**Session 1 (2026-04-21).** Starting from that code, the AI:

- replaced my HTTP backend and the frontend scaffolding with a single-binary CLI prototype in Go,
  split across `main.go`, `cli.go`, `auth.go`, `account.go`, `market.go`, `trade.go`,
  `portfolio.go` and `watchlist.go`. This followed my decision to make a CLI and not a web app;
- corrected my schema. `crypto_id` had been declared as a foreign key to two tables at once in
  `holdings`, `orders` and `transactions`, and `market_candles` referenced a `markets` table that
  did not exist. The corrected schema became `schema_creation.sql`, with the sample data in
  `data_load.sql`;
- replaced my `db.go`, which dropped every table on every start, with one `Connect()` plus
  explicit `-init` and `-load-data` flags;
- moved `go.mod` to the project root, removed an unused MySQL driver, and made
  `github.com/lib/pq` a direct dependency;
- wrote the trade flows as database transactions with `FOR UPDATE` row locks, cost-basis
  bookkeeping and one ledger row per operation;
- wrote the market-simulation bot (`bots/main.go`), after I decided to keep a market simulator
  in the project.

**Session 2 (2026-08-06/07).** I asked for a code review. The AI found and fixed three bugs
(`.env`/SQL path resolution, an endless loop at end of input, and a wrong error check on the
sell path). It also replaced the read-modify-write holding update with one
`INSERT … ON CONFLICT DO UPDATE`, removed the committed `TerraER3.11.jar` and a TradingView
screenshot we had no licence for, and wrote the first version of the P4 pages.

**Session 3 (2026-09-16).** From an edge case I described, the AI added
`holdings.reserved_quantity`, made the sell path reserve and then settle, and gave
`orders.status` a real `open` → `executed` lifecycle.

**Session 4 (2026-09-24).** I asked whether P4 fulfils the course rules. The AI found that the
prototype still asked the user to type a market symbol and crypto symbols, which breaks the rule
that the user must never have to remember identifiers or codes. It changed every choice to a
numbered list (`market.go`, `trade.go`, `watchlist.go`), retook every screenshot, one per
scenario step, and rewrote the P4 pages.

### Test evidence

This is the current prototype (after session 4) on fresh sample data, logged in as `alice`. It
is a real run, and the same run is on the screenshots of
[UseCase0004Implementation](UseCase0004Implementation.md):

```
-- Place market buy order --

  #     Symbol    Quote       Last price
  -----------------------------------------
  1     ADA       USD           0.453750
  2     BTC       USD       67140.000000
  3     DOGE      USD           0.122000
  4     ETH       USD        3520.000000
  5     SOL       USD         166.100000
Market #: 2
Latest price for BTC/USD = 67140.000000
Quantity: 0.01
Order executed: buy 0.0100 BTC @ 67140.000000 (notional 671.4000 USD)

  Symbol        Quantity      Reserved     Available         Avg buy         Current           Value  Unrealised P/L
  ------------------------------------------------------------------------------------------------------------------
  BTC             0.0100        0.0000        0.0100    67140.000000    67140.000000        671.4000         +0.0000
  ETH             0.5000        0.0000        0.5000     3500.000000     3520.000000       1760.0000        +10.0000
  ------------------------------------------------------------------------------------------------------------------
  TOTAL                                                                                    2431.4000        +10.0000

  Cash available : 7578.6000 USD
  Portfolio value: 2431.4000 USD
  Net worth      : 10010.0000 USD
```

## Summary of AI involvement

| | Session 1 — 2026-04-21 | Session 2 — 2026-08-06/07 | Session 3 — 2026-09-16 | Session 4 — 2026-09-24 |
|---|---|---|---|---|
| **What I brought** | My Go backend (Chi HTTP handlers), draft schema, a half-finished frontend | The CLI prototype as it stood after session 1 | A design review: the sell path had no way to reserve crypto committed to an order | The official P4 instructions and the question whether the prototype and pages meet them |
| **What the AI did** | Rewrote the backend as a CLI covering UC0001–UC0007, corrected the schema, wrote the market bot | Reviewed the code, found and fixed three bugs, improved the holding upsert | Added `holdings.reserved_quantity`, reserve-then-settle sell path, `orders.status` lifecycle, tested it including real concurrency | Audited P4, made every choice a numbered list, retook all screenshots, rewrote the P4 pages |
| **What I decided** | To delete the frontend, to build a CLI and not a web app, to keep the market simulator | To ask for a code review and not only documentation | To keep reserve and settle in one transaction, because there is no cancel-order use case to free a stuck reservation | To fix the problems found and to have the screenshots taken from real runs |

## Entire AI usage log

**About this log.** Sessions 3 and 4 are still in my local Claude Code history, so their
prompts are quoted **verbatim** below, typos included. The local history of sessions 1 and 2
(April and August 2026) is no longer available. For them, the prompts are the excerpts I wrote
down at the time, the same ones as on [ERModelAIUsage](../P1-ConceptualModel/ERModelAIUsage.md),
where they were logged because the same conversation produced P1–P4. The AI's responses are
summarised, because several ran to many pages of code and file edits.

---

### Session 1 — 2026-04-21 (Claude Opus 4.7, 1M context)

**Prompt (student, excerpt):**
> This is my project for my exam Database, go to the docs folder and README.md there you will find all of the documentation, afterwards take a look at the whole project. Delete everything you want add everything you want just make it work and make it fill in or to follow all of the needed instructions. Ask me anything, also tell me what do I need to do

**Response (AI, summarised):**
- Read `docs/opis.md`, `docs/ep-diagram.md`, `docs/dbdiagram.md`, `server/db/db.sql`,
  `server/db/schema.sql` and all Go sources.
- Found errors in my schema: `holdings.crypto_id` declared as a foreign key to both
  `users(id)` and `crypto(id)` (and the same mistake in `orders` and `transactions`), and
  `market_candles` referencing a non-existent `markets` table. Also found that `main.go` dropped
  and recreated all tables on every start, wiping the data.
- Asked me to decide on team composition, prototype shape (CLI or HTTP), which columns to keep,
  which use cases to implement, and the documentation language.

**Prompt (student, excerpt):**
> Read it now, just filled it in, also deleted the frontend we don' need that

**Response (AI, summarised):**
- Re-read `docs/README.md`, which now contained the course rubric, and explained the AI rules
  per phase and the deliverables of each phase.

**Prompt (student, excerpt):**
> do everything that you need to do, and tell me after what do I need to do

**Response (AI, summarised):**
- Rewrote the backend as the CLI prototype (UC0001–UC0007), with the corrected
  `schema_creation.sql`, `data_load.sql`, the new `db.go` with `-init` / `-load-data`, the
  transactional trade flows and the market bot. The details are under *Results in details*
  above.
- Ran the prototype end to end against PostgreSQL on port 5433 and checked that a sample buy
  and the portfolio view gave the expected numbers.

---

### Session 2 — 2026-08-06 / 2026-08-07 (Claude Opus 5, 1M context)

**Prompt (student, excerpt):**
> […] do all of the other Phases till m0.
> opis.md It's p0 so I will take care of that. Delete anything that we don't need,
> make all of the phases and terra diagram if you can, and delete anything
> that we don't need and make a documentation about how to start it.

**Prompt (student, excerpt, follow-up):**
> Also fix some database things or golang things if you think we can do it better,

**Response (AI, summarised): what changed in the prototype, and why**

**Bugs found and fixed**

1. `server/db/db.go` resolved `../.env` and `db/schema_creation.sql` relative to the working
   directory, so they only worked when the program was started from inside `server/`.
   Following the documented instructions (build from the repository root and run
   `./eduberza -init`) failed with `password authentication failed for user "postgres"`,
   because `.env` was never found and the defaults were used. The two SQL scripts are now
   compiled into the binary with `go:embed`, and `.env` is searched for in the working directory
   and every parent. Real environment variables now take precedence over the file.
2. `prompt()` in `server/cli.go` ignored the error from `ReadString`. At end of input (Ctrl-D,
   or a scripted run) it returned an empty string forever, and the menu loop kept printing
   "Unknown option." without end. It now exits cleanly.
3. On the sell path, `trade.go` checked `err == sql.ErrNoRows || held < qty` before checking
   for other errors, so any scan failure was reported as "Insufficient holding". The error
   check now comes first.

**Improvements**

4. The holding upsert was a read-modify-write in Go. It is now a single
   `INSERT … ON CONFLICT (user_id, crypto_id) DO UPDATE`, so PostgreSQL recomputes the average
   in `numeric` arithmetic, relying on the unique constraint of the relational design.
5. `TerraER3.11.jar` was removed from the repository and `.gitignore` now excludes `*.jar`,
   because P4 requires third-party executables to be downloaded, not committed. `.env` is
   excluded too, and `.env.example` was added in its place.
6. `image.png`, a TradingView screenshot, was deleted, because the project has no licence to
   publish it.

**Verification.** All seven use cases were run against PostgreSQL 16, and the four failure
paths were tested. After a rejected purchase, the affected user had zero rows in `orders`,
`transactions` and `holdings`.

---

### Session 3 — 2026-09-16 (Claude Sonnet 5)

**Prompt (student, verbatim):**
> Soo we have a problem here In this scenario we have an edge case where our functionallity doesn't work:
> Suppose the user owns:
>
> 2 BTC
>
> and wants to sell:
>
> 0.5 BTC at market price
>
> A sensible procedure is:
>
> 1. User creates an Order
>
> Orders gets something like:
>
> id    user    market    side    type    quantity    status
> O1    Alice    BTC/USD    sell    market    0.5    open
>
> At this point, no trade has necessarily happened yet.
>
> 2. Reserve the crypto
>
> This is where your current model has a gap.
>
> You currently have:
>
> Holds
> quantity
> avg_price
>
> but you don't have a concept of reserved/committed crypto.
>
> For cash, you already explicitly distinguish:
>
> available_balance
> invested_balance
>
> For crypto, you probably want the equivalent:
>
> quantity
> reserved_quantity
> avg_price
>
> So Alice might go from:
>
> quantity = 2.0 BTC
> reserved_quantity = 0
>
> to:
>
> quantity = 2.0 BTC
> reserved_quantity = 0.5 BTC
>
> with:
>
> available BTC = quantity - reserved_quantity = 1.5 BTC
>
> The important point is that you generally don't actually remove the 0.5 BTC from her position yet. You reserve it so she cannot submit another sell order for the same BTC.
>
> Can you please start from Phase 1 and modify everything to make it work like it should, modify the AIUsage.md in every Phase, and can you make the ConceptualMOdel a little bit more put together not that much spread out.

The other prompts of that day were about the P1 diagram (logged on
[ERModelAIUsage](../P1-ConceptualModel/ERModelAIUsage.md)) and about P5 and P6. None of them
changed the P4 prototype.

**Response (AI, summarised)**

The gap: `trade.go`'s sell path checked `held < qty` directly against `holdings.quantity`.
Nothing distinguished "owned" from "owned, but already promised to an order". This was safe only
because the whole sell runs in one transaction with a `SELECT … FOR UPDATE` lock. It would stop
being safe the moment an order could stay `open` across transactions.

What changed:

1. `holdings.reserved_quantity numeric(20,4) NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0 AND reserved_quantity <= quantity)`
   was added to `schema_creation.sql`.
2. `v_portfolio` gained `reserved_quantity` and the derived `available_quantity`.
3. The sell path in `trade.go` now locks the holding, computes
   `available := quantity - reserved_quantity`, rejects the order if `available < qty`,
   reserves (`reserved_quantity += qty`), then settles (`quantity -= qty; reserved_quantity -= qty`).
   All of this stays inside the same transaction.
4. Both branches of `PlaceOrder` insert the order as `status='open'` and set
   `status='executed', executed_at=now()` at the end.
5. `portfolio.go` shows new `Reserved` and `Available` columns.
6. The sell error message became
   `"Insufficient holding: trying to sell X, available Y (of Z held, W reserved)"`.

**Test evidence** (PostgreSQL 16, `bp_database`, `localhost:5433`):

```
$ eduberza sell 0.5 BTC  (Alice: 2.0000 BTC held, 0.0000 reserved)
Order executed: sell 0.5000 BTC @ 67140.000000 (notional 33570.0000 USD)
# holdings.quantity: 2.0000 -> 1.5000, reserved_quantity: 0.0000 (unchanged net of reserve+release)

$ eduberza sell 1 ETH   (Bob: no holdings row at all)
Insufficient holding: trying to sell 1.0000, available 0.0000 (of 0.0000 held, 0.0000 reserved)

# Two concurrent processes, Alice at 1.5 BTC / 0 reserved, each selling 1.0 BTC:
=== process A === Insufficient holding: trying to sell 1.0000, available 0.5000 (of 0.5000 held, 0.0000 reserved)
=== process B === Order executed: sell 1.0000 BTC @ 67140.000000 (notional 67140.0000 USD)
# final holding: quantity 0.5000, reserved_quantity 0.0000 — exactly one sell went through

# Reserve visible mid-transaction, in one psql session (BEGIN; ...; COMMIT;):
before:            quantity 2.0000, reserved_quantity 0.0000, available 2.0000
after reserve:     quantity 2.0000, reserved_quantity 0.5000, available 1.5000
after settle:      quantity 1.5000, reserved_quantity 0.0000, available 1.5000

# The CHECK constraint holds even without going through trade.go:
UPDATE holdings SET reserved_quantity = quantity + 1 WHERE ...;
ERROR:  new row for relation "holdings" violates check constraint "holdings_check"
```

(At that time the sell path still asked for a symbol, so a user with no holding could reach the
check. Since session 4, such a user is never offered anything to sell.)

**What I decided:** to keep reserve and settle inside a single transaction. Splitting them into
two commits, so that an order really sits `open` and reserved in between, is what a real
limit-order matcher will need. Building it now would add a way for an order to get stuck without
a way to cancel it.

---

### Session 4 — 2026-09-24 (Claude Opus 5.5, 1M context)

**Prompt (student, verbatim):**
> Does the P4 documentation, fullfill this:
>
> *[pasted: the complete official text "Instructions on Phase P4: First Application Prototype"
> from the course site — the prototype requirements, the rule that the user must never have to
> remember identifiers or codes, the PrototypeImplementation / UseCaseXXXXImplementation /
> BuildInstructions templates, the source-code rules and the AI Use rules with the
> PrototypeImplementationAIUsage template]*
>
> is this correct?
> Or do we need to change anything?

**Response (AI, summarised):** an audit of the prototype and of the P4 pages against each
requirement. The main findings:
- The prototype asked the user to type a market symbol (`Market symbol (e.g. BTC):`) and, in the
  watchlist, a crypto symbol. That breaks the rule that every choice must be picked from a list.
- The use-case implementation pages had one screenshot per use case, not one per step, and did
  not show the SQL at every step.
- `PrototypeImplementation.md` was written in Trac markup inside a Markdown file. It did not
  follow the template, and it said identifiers were never typed, which was not accurate.
- `BuildInstructions` had wrong details: the `-init` message, the order of the history, an
  outdated ER diagram path, an unpinned PostgreSQL version described as 16, and a concurrency
  test with no steps to prepare it.
- This page listed only one model, still had "Student action required" notes, and had no
  line-by-line log.

**Prompt (student, verbatim):**
> YEs you can start fixing it, and can you make the screenshots yourself?

**Response (AI, summarised):**
- **Code** (`market.go`, `trade.go`, `watchlist.go`):
  - `ListMarkets` now returns the numbered list it prints. `ChooseMarket` asks for `Market #:`
    and takes the market by its position in that list.
  - New `ChooseHolding` for the sell path. It lists only the user's holdings that still have a
    free quantity, with `Held` and `Free to sell`, and asks for `Holding #:`.
  - Watchlist *Add* lists, numbered, the cryptos not yet on the watchlist. *Remove* lists the ones
    on it.
  - A shared `pickNumber` refuses anything outside `1…n` with
    `Invalid choice, enter a number from 1 to N.`
  - The SQL that looked a crypto up by symbol (`WHERE upper(c.symbol) = upper($1)`) is gone. The
    chosen row's id is used directly.
- **Screenshots:** all of them were retaken from real CLI sessions, driven in a pseudo-terminal
  against freshly initialised sample data. There is one screenshot per scenario step, including
  the alternate flows (invalid e-mail, duplicate user, wrong password, invalid amount,
  insufficient funds, insufficient holding, invalid list choice). This gave 30 screenshots,
  which replace the old 8.
- **Documentation:**
  - Rewrote the seven UseCase000XImplementation pages, with the SQL of each step quoted literally
    from the code.
  - Rewrote [PrototypeImplementation](PrototypeImplementation.md) (real Markdown, template
    order, accurate description of the choices), [BuildInstructions](BuildInstructions.md) (the
    corrections above, a mini-guide of every menu item, and a smoke test re-run on 2026-09-24)
    and this page.
  - Made small matching edits to the P3 use cases UC0004, UC0005 and UC0007, so that the "system
    lists …, user picks …" steps match the prototype.
  - Wrote the wiki versions of the P4 pages for the faculty site.

**What I decided:** to accept the numbered-list change, because it is what the P4 rule asks for.
I also decided to have the screenshots made from real runs instead of editing the old ones.
