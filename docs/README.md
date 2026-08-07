# EduBerza

## Short description

*P0 — write 150–200 words here in your own words. AI-generated text is not
allowed in this phase.*

*Your own Macedonian draft is in [`opis.md`](P0-ProjectDefinition/opis.md); the material to cover is
what data the database holds (users, crypto assets, markets, orders, holdings,
transactions, market trades, candles, watchlists), who it is for (beginner
traders), and what kind of project it is.*

## Team members

- *Your First Name Last Name — Index XXXXXX*

## Course

Databases in 2025/2026/Winter

## Under the supervision of

Prof. Dr. Vangel V. Ajanovski

## How this folder maps to the wiki

The files here are grouped into one folder per phase for convenience. **The wiki
is flat** — when you publish, each file becomes a page named exactly after the
file, with no folder prefix and with capitalisation preserved: `About`,
`ERModel`, `RelationalDesign`, `UseCaseModel`, `UseCase0001`, …,
`PrototypeImplementation`, `BuildInstructions`, and the four `*AIUsage` pages.
Attachments (`ERModel_v01.xml`, `ERModel_v01.png`, `schema_creation.sql`,
`data_load.sql`, `relational_schema.jpg`, the screenshots) attach to the page
that documents them.

| Folder | Phase | Wiki pages produced |
|--------|-------|---------------------|
| `P0-ProjectDefinition/` | P0 | `About` (+ this front page) |
| `P1-ConceptualModel/`   | P1 | `ERModel`, `ERModelAIUsage` |
| `P2-RelationalDesign/`  | P2 | `RelationalDesign`, `RelationalDesignAIUsage` |
| `P3-UseCaseModel/`      | P3 | `UseCaseModel`, `UseCase0001`–`UseCase0007`, `UseCaseModelAIUsage` |
| `P4-Prototype/`         | P4 | `PrototypeImplementation`, `UseCase000XImplementation`, `BuildInstructions`, `PrototypeImplementationAIUsage` |

`Instructions.md` is the condensed course rubric — reference material, not a
submission. `P0-ProjectDefinition/opis.md` and `P1-ConceptualModel/ep-diagram.md`
are your own working notes, kept because they are the evidence that the initial
model was yours before any AI was used.

The two SQL scripts deliberately stay in `server/db/` rather than moving into
`P2-RelationalDesign/`: they are compiled into the prototype binary with
`go:embed`, which requires them to sit inside the Go package. Attach them to the
`RelationalDesign` page from there.

## Content

| Phase | Link | Status |
|-------|------|--------|
| P0 | [About](P0-ProjectDefinition/About.md) | Draft — needs your own text |
| P1 | [ERModel](P1-ConceptualModel/ERModel.md) | Finished, awaiting approval |
| P2 | [RelationalDesign](P2-RelationalDesign/RelationalDesign.md) | Finished, awaiting approval |
| P3 | [UseCaseModel](P3-UseCaseModel/UseCaseModel.md) | Finished, awaiting approval |
| P4 | [PrototypeImplementation](P4-Prototype/PrototypeImplementation.md) | Finished, awaiting approval |
| P5 | *Normalization* | Not started |
| P6 | *Complex DB Reports* | Not started |
| P7 | *Advanced Database Development* | Not started |
| P8 | *Advanced Application Development* | Not started |
| P9 | *Other topics (Performance, Security)* | Not started |

Keep the Status column current yourself — *started → completed → revised →
approved → final* — after each consultation.

Note: P0–P4 alone are not enough for a passing grade; at least some of P5–P9 are
required. P5 is the recommended next one.

## Phase attachments

| File | Phase | What |
|------|-------|------|
| [`ERModel_v01.xml`](P1-ConceptualModel/ERModel_v01.xml) | P1 | TerraER source of the ER diagram |
| [`ERModel_v01.png`](P1-ConceptualModel/ERModel_v01.png) | P1 | Exported diagram image |
| [`../server/db/schema_creation.sql`](../server/db/schema_creation.sql) | P2 | DDL — drops and recreates the `project` schema |
| [`../server/db/data_load.sql`](../server/db/data_load.sql) | P2 | DML — truncates and reloads sample data |
| [`relational_schema.jpg`](P2-RelationalDesign/relational_schema.jpg) | P2 | Crow's-foot diagram exported from DBeaver |

## Use cases (P3)

[UC0001](P3-UseCaseModel/UseCase0001.md) Register ·
[UC0002](P3-UseCaseModel/UseCase0002.md) Log in ·
[UC0003](P3-UseCaseModel/UseCase0003.md) Deposit ·
[UC0004](P3-UseCaseModel/UseCase0004.md) Buy ·
[UC0005](P3-UseCaseModel/UseCase0005.md) Sell ·
[UC0006](P3-UseCaseModel/UseCase0006.md) Portfolio ·
[UC0007](P3-UseCaseModel/UseCase0007.md) Watchlist

## AI usage logs

Required by the phase rules for every phase where AI was used. P0 does not have
one because AI use is forbidden there.

- [ERModelAIUsage](P1-ConceptualModel/ERModelAIUsage.md) (P1)
- [RelationalDesignAIUsage](P2-RelationalDesign/RelationalDesignAIUsage.md) (P2)
- [UseCaseModelAIUsage](P3-UseCaseModel/UseCaseModelAIUsage.md) (P3)
- [PrototypeImplementationAIUsage](P4-Prototype/PrototypeImplementationAIUsage.md) (P4)

## Build & run

See [BuildInstructions](P4-Prototype/BuildInstructions.md), or [`../README.md`](../README.md)
for the four-command quick start.
# bp
