# Entity-Relationship Model AI Usage

## Name of AI service/solution that was used

**Claude Code** (Anthropic)

- **URL:** https://claude.com/claude-code
- **Type of service/subscription:** Claude subscription. Session 1 used model
  Claude Opus 4.7 (1M context); session 2 used Claude Opus 5 (1M context).

## Final result

### Diagram

`ERModel_v01.xml` / `ERModel_v01.png`.

**Declaration of how the diagram was produced.** The initial model is the
student's own: the entity and attribute list in [`ep-diagram.md`](ep-diagram.md),
written in Macedonian before any AI was involved. In session 2 the AI turned that
list into the TerraER diagram file, and while doing so proposed three changes to
the initial model, all three listed in the model history on
[ERModel](ERModel.md#entity-relationship-model-history):
promoting `Markets` to its own entity set, re-expressing `holdings` and
`watchlist_items` as M:N relationships with attributes rather than entity sets
with foreign keys, and marking `avg_price` as derived.

The diagram was not drawn by hand in the TerraER GUI. It was generated
programmatically by constructing TerraER's own figure objects
(`EntidadeFigure`, `RelacionamentoFigure`, `AtributoFigure`,
`AtributoChaveFigure`, `AtributoDerivadoFigure` and the labelled line-connection
figures) and serialising them with TerraER's own
`DOMStorableInputOutputFormat` — the same writer the application uses when you
choose *Save*. The file is therefore a normal TerraER document: it was verified
by reading it back through TerraER's own reader and comparing the figure count
(144), and it opens and can be edited in TerraER 3.11 like any hand-drawn
diagram. `ERModel_v02.xml` is the student's own review pass over v01, done by
hand in the GUI.

`ERModel_v03.xml` / `ERModel_v03.png` (session 3, 2026-09-16) were produced the
same way, this time as a genuine load–modify–save round trip through TerraER's
own classes rather than a from-scratch build: `ERModel_v02.xml` was read with
the application's real `DrawFigureFactory` and `DOMStorableInputOutputFormat`
into a live `QuadTreeDrawing`, one `AtributoFigure` was cloned from the
existing `quantity` attribute of `Holds` (to inherit its exact styling) and
relabelled `reserved_quantity`, a matching `LabeledLineConnectionFigure` was
added between it and the `Holds` diamond (`ChopDiamondConnector` /
`ChopEllipseConnector`, the same connector pair every other attribute of
`Holds` uses), and every entity and relationship — together with its own
attributes, moved by the same offset — was translated proportionally toward
the diagram's centroid to close up excess canvas space, after which every
connection figure had `updateConnection()` called so its drawn path follows
the moved figures. The result was written with the real writer and rendered to
PNG with TerraER's own `ImageOutputFormat`, and re-verified by reading
`ERModel_v03.xml` back and confirming the figure count (146 = 144 + the new
attribute + its line) and that all five attributes of `Holds` resolve with the
expected connector classes. No figure was hand-edited in XML.

### Model description

See [ERModel](ERModel.md).

## Summary of AI involvement

Work on this project happened in three working sessions.

| | Session 1 | Session 2 | Session 3 |
|---|---|---|---|
| **When** | 2026-04-21 | 2026-08-06 / 2026-08-07 | 2026-09-16 |
| **Model** | Claude Opus 4.7 (1M context) | Claude Opus 5 (1M context) | Claude Sonnet 5 |
| **Phases advanced** | P1, P2, P3 and the first working prototype | The ER diagram file, P4 documentation, bug fixes | `Holds.reserved_quantity` added across P1–P4 |
| **My starting material** | `ep-diagram.md`, `opis.md`, my existing Go backend and draft SQL | Everything from session 1, plus the phase rubric | Everything from sessions 1–2, plus a design review of the sell-order flow |

In **session 1** I brought my own data model (`ep-diagram.md`, written in
Macedonian before any AI was involved) and my own draft schema and Go backend. I
used the AI to review them, and it found real errors in my SQL that I had missed
— most seriously that I had declared `crypto_id` as a foreign key to two
different tables at once, in three separate tables. I decided the corrections to
adopt, chose to go solo, chose a CLI prototype over an HTTP one, and chose
English for the documentation. The output of that session was the corrected
schema, the sample-data script, the use-case model and the working prototype.

In **session 2** I came back to produce the deliverable I was still missing — the
TerraER diagram file itself — and to finish the P4 documentation. I also asked
for a review pass over the database and Go code, which turned up three further
bugs (see [PrototypeImplementationAIUsage](../P4-Prototype/PrototypeImplementationAIUsage.md)).

In **session 3** I described a concrete edge case I'd spotted in the sell flow
— nothing stopped a user from placing a second sell order against crypto
already promised to a first, unsettled one — and asked the AI to fix it
starting from P1 and carry the fix through every phase. This added
`reserved_quantity` to `Holds` and changed the sell path in `trade.go` to use
it; see the model history on
[ERModel](ERModel.md#entity-relationship-model-history) (v03) and the log
below.

Below is the log, one entry per exchange. My prompts are quoted as **excerpts**:
the wording is my own, unaltered, but I have left out scheduling remarks and
other working chatter that says nothing about the model or the code. Typos are
kept as they were. The *Intent* line above each prompt is my own note on what I
was trying to achieve. AI responses are summarised rather than quoted in full,
because several ran to many pages of code and file edits. The complete
unabridged transcript is in my Claude Code session history and can be produced
on request.

## Entire AI usage log

---

### Session 1 — 2026-04-21

**Intent:** hand the AI the whole project and the course rubric, and have it
audit my existing model and code against the phase requirements before I commit
to anything.

**Prompt (student, excerpt):**
> This is my project for my exam Database, go to the docs folder and README.md there you will find all of the documentation, afterwards take a look at the whole project. Delete everything you want add everything you want just make it work and make it fill in or to follow all of the needed instructions. Ask me anything, also tell me what do I need to do

**Response (AI, summarised):**
- Read `docs/opis.md`, `docs/ep-diagram.md`, `docs/dbdiagram.md`, `server/db/db.sql`, `server/db/schema.sql`, all Go sources.
- Flagged bugs in the initial schema:
  - `holdings.crypto_id` declared as a foreign key to both `users(id)` and `crypto(id)`; should be a separate `user_id` column.
  - Same mistake in `orders` and `transactions`.
  - `market_candles` referenced a non-existent `markets` table.
  - `main.go` dropped and recreated all tables on every startup, wiping data.
- Proposed a single authoritative schema, to be placed in `server/db/schema_creation.sql`, based on `docs/ep-diagram.md` and `docs/dbdiagram.md` with the above issues fixed.
- Asked the student for decisions: team composition, prototype shape (CLI vs HTTP), whether to keep `available_balance`, `invested_balance`, `secret_question`, `secret_answer`, which use cases to implement, language of documentation.

**Intent:** I had just pasted the course rubric into `README.md` and removed the
half-finished frontend, so that the AI would plan against the actual phase
requirements and against a backend-only prototype.

**Prompt (student, excerpt):**
> Read it now, just filled it in, also deleted the frontend we don' need that

**Response (AI, summarised):**
- Re-read `docs/README.md`, which now contained the course phase rubric (P0–P9).
- Explained the constraints each phase places on AI usage (P0 forbids AI; P1–P4 allow AI only to improve the student's own initial model and require an AIUsage log).
- Listed the deliverables per phase and asked the remaining questions.

---

### Session 2 — 2026-08-06 / 2026-08-07

**Intent:** re-read the rubric from scratch after the gap, reduce it to a
checklist of what each phase actually has to produce, confirm TerraER runs on
this machine.

**Prompt (student, excerpt):**
> We will start from the begining in some ways, please read first docs/insturctions.md
> The goal is to finish with milestone 0 so I can publish it […]
> Read the Instuctions.md like I said and delete everything that you think we don't need
> and for each phrase tell me what do I need to submit and how to do it. and can you also
> do the thing with TerraER3.11.jar?

**Response (AI, summarised):**
- Read the phase rubric and condensed `Instructions.md` to a per-phase checklist
  of deliverables, keeping every requirement and every load-bearing filename.
- Confirmed TerraER 3.11 runs on the installed OpenJDK 21 and launched it.
- Listed, per phase, what has to be submitted and how; flagged that P0's
  deliverables are wiki pages, that the EPRMS proposal is a prerequisite.
- Flagged `image.png` (a TradingView screenshot) as material the project has no
  licence to publish.

**Intent:** produce the artefacts still missing for P1–P4 — above all the TerraER
diagram — while keeping P0 for myself, since AI use is forbidden there.

**Prompt (student, excerpt):**
> […] do all of the other Phases till m0.
> opis.md It's p0 so I will take care of that. Delete anything that we don't need,
> make all of the phases and terra diagram if you can, and delete anything
> that we don't need and make a documentation about how to start it.

**Intent:** ask for a review pass over the schema and the Go code rather than
only documentation, on the grounds that a prototype I have to defend in person
should not have known defects in it.

**Prompt (student, excerpt, follow-up):**
> Also fix some database things or golang things if you think we can do it better,

**Response (AI, summarised) — the part relevant to P1:**
- Read `ep-diagram.md` (the student's own initial model) and the existing
  `schema_creation.sql`.
- Reverse-engineered TerraER's file format from the distributed jar to learn the
  element names it stores figures under (`ent`, `rel`, `atr`, `atrchave`,
  `atrderivado`, `llabelUm`, `llabelMuitos`, `llabelDoubleUm`,
  `llabelDoubleMuitos`, …).
- Generated `ERModel_v01.xml` and `ERModel_v01.png` as described above, in Chen
  notation: 8 entity sets, 10 relationships, 57 attributes, cardinality labels
  on every relationship line and double lines for total participation.
- Proposed the three changes to the initial model recorded in the model history.
- Rewrote [ERModel](ERModel.md) with the per-entity documentation, candidate-key
  justifications and attribute types the phase template requires.

---

> **Student action required.** Two things, in this order:
>
> 1. Open `ERModel_v01.xml` in TerraER, read the whole diagram, and change what
>    you disagree with. Save the result as `ERModel_v02.xml` with a matching PNG
>    and add a history line. The phase rules require that the model be yours;
>    the generated v01 is a starting point to review and take over, not an
>    answer to submit unread.
> 2. Verify that this log matches your recollection and append the full text of
>    any further prompts. The complete transcript is in your Claude Code session
>    history.

---

### Session 3 — 2026-09-16

**Intent:** describe a concrete gap I'd found in the sell-order design — the
model had no way to represent crypto committed to an order that had not yet
settled — and have the AI trace the fix through every phase rather than patch
`trade.go` alone.

**Prompt (student, excerpt):**
> Suppose the user owns 2 BTC and wants to sell 0.5 BTC at market price. […] You
> currently have Holds: quantity, avg_price but you don't have a concept of
> reserved/committed crypto. For cash, you already explicitly distinguish
> available_balance, invested_balance. For crypto, you probably want the
> equivalent: quantity, reserved_quantity, avg_price. […] Can you please start
> from Phase 1 and modify everything to make it work like it should, modify
> the AIUsage.md in every Phase, and can you make the ConceptualModel a little
> bit more put together not that much spread out.

**Response (AI, summarised):**
- Read every phase document and the live `server/trade.go`, `portfolio.go` and
  `schema_creation.sql` to confirm the actual gap: the sell path checked
  `holdings.quantity` directly, with nothing recording that part of a position
  was already promised to another order.
- Added `reserved_quantity` to `Holds` (P1), `holdings` (P2), the sell scenario
  SQL (P3), and `trade.go`/`portfolio.go`/`schema_creation.sql` (P4) — one
  attribute threaded consistently through all four phases rather than a
  patch confined to the Go code.
- Changed the sell path to lock the holding row, compute
  `available = quantity − reserved_quantity`, reserve (`reserved_quantity +=
  qty`) and then settle (`quantity -= qty; reserved_quantity -= qty`) inside
  the same transaction — keeping the existing all-or-nothing guarantee rather
  than splitting into two commits, which would leave an unresolvable `open`
  order if the process died in between and there is no cancel use case to
  recover it.
- Made both buy and sell orders genuinely pass through `status='open'` before
  `status='executed'`, instead of being inserted as `'executed'` directly, so
  the lifecycle the ER model already claimed for `Orders` is real.
- Added a `CHECK (reserved_quantity >= 0 AND reserved_quantity <= quantity)`
  constraint and exposed `reserved_quantity`/`available_quantity` on
  `v_portfolio` and in the CLI's portfolio table, so the new field is
  observable rather than a column nobody can see.
- Restructured this phase's [ERModel](ERModel.md) into short rationale + a
  compact attribute table per entity/relationship, per the "more put together,
  not that much spread out" request — no content was removed, only
  reformatted.
- Verified the fix against the live database (`bp_database` on `localhost:5433`):
  ran two concurrent `sell 1.0 BTC` attempts against a holding with only 1.5
  BTC available — exactly one succeeded, the other correctly reported
  insufficient holding — and ran the reserve/settle sequence by hand in `psql`
  to show `reserved_quantity` at 0.5 mid-transaction. Both are recorded in
  [UseCase0005Implementation](../P4-Prototype/UseCase0005Implementation.md).

**What I decided:** to keep reserve and settle inside one transaction rather
than two (see the AI's reasoning above — I agreed with it, since a stuck
`open` order with no cancel command would be a worse bug than the one being
fixed).

**Follow-up, same day:** I asked for `ERModel_v03.xml`/`.png` after all,
having noticed the PNG still showed v02 with no `reserved_quantity` on it, and
asked at the same time for the diagram to be a little more compact — it had a
lot of empty canvas in the middle. The AI drove TerraER's own classes directly
(load → clone the `quantity` attribute → relabel it → add its connecting line
→ pull every cluster toward the centroid → save → render), described in full
under [Diagram](#diagram) above, rather than hand-editing the XML or asking me
to do it in the GUI. I reviewed the rendered PNG before accepting it.

**Second follow-up, same day:** the first `ERModel_v03.png` rendered with a
black background instead of white, unlike v01/v02. Cause: TerraER's
`ImageOutputFormat` defaults to an ARGB image and paints its background with
zero alpha (transparent), not opaque white; whatever displayed the PNG then
flattened that transparency onto black instead of white. Fixed by exporting
through the same `ImageOutputFormat.toImage(...)` call for figure geometry,
but compositing its result onto an explicitly white-filled opaque `RGB` image
before saving, rather than trusting the library's own (transparent) output.
Verified the fix by reading back the corner pixel of the written PNG as pure
white `(255,255,255)`, matching `ERModel_v02.png`.


### Session 4 — 2026-09-24 (Claude Opus 5.5): v04 after P7

**Prompts (student, verbatim):**
> But this order_events is added after Phase 7 right? can we add that too?

> can you make the ERmodel again with TerraER file to update it? and tell that after P7 we added this

> Make it with a white background like earier versions

**Response (AI, summarised):**

- Explained that the P7 changes must also appear in P1 and P2, since both must describe the
  current data structure.
- Built `ERModel_v04.xml` in TerraER's own file format by taking `ERModel_v03.xml` unchanged
  and appending the new elements with the same XML structure TerraER uses:
  - the attribute `reserved_balance` on `Users`;
  - the attribute `filled_quantity` on `Orders`;
  - the relationships `FillsBuy` and `FillsSell` (Orders 1 : N MarketTrades, partial);
  - the entity set `OrderEvents` (key `id`, `event_type`, `quantity`, `price`,
    `status_after`, `created_at`) with `Logs` (Orders 1 : N OrderEvents, total on
    OrderEvents).
- Rendered `ERModel_v04.png` with TerraER 3.14's own drawing classes (loading the `.xml`
  exactly as TerraER does and using its image export), on a white background and trimmed like
  the earlier versions.
- Updated [ERModel](ERModel.md) (title v.04, new attribute rows, the `OrderEvents` section, the
  three relationships, and a v04 history entry stating these were added after P7).

**What I decided:** to add the P7 structure to the ER model. The new elements are placed
automatically, so the layout can be tidied by hand in TerraER.
