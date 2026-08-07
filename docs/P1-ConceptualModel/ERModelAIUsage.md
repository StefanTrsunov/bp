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
diagram. Subsequent versions (`ERModel_v02.xml` onward) are edited by the student
in the GUI.

### Model description

See [ERModel](ERModel.md).

## Summary of AI involvement

Work on this project happened in two working sessions, several months apart.

| | Session 1 | Session 2 |
|---|---|---|
| **When** | 2026-04-21 | 2026-08-06 / 2026-08-07 |
| **Model** | Claude Opus 4.7 (1M context) | Claude Opus 5 (1M context) |
| **Phases advanced** | P1, P2, P3 and the first working prototype | The ER diagram file, P4 documentation, bug fixes |
| **My starting material** | `ep-diagram.md`, `opis.md`, my existing Go backend and draft SQL | Everything from session 1, plus the phase rubric |

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
