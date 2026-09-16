# Normalization AI Usage

## Name of AI service/solution that was used

**Claude Code** (Anthropic)

- **URL:** https://claude.com/claude-code
- **Type of service/subscription:** Claude subscription, model Claude Sonnet 5.

## Final result

### Results in details / description

The AI:

- Built the single de-normalized relation `R_EDUBERZA` (68 attributes) by taking every
  attribute from every entity and attributed relationship in
  [ERModel](../P1-ConceptualModel/ERModel.md), plus the foreign-key-style linking attributes
  that the eight attributeless relationships need to be representable in one flat table at
  all, and disambiguating every repeated name (`id`, `created_at`, `quantity`, `type`, …)
  with a per-origin prefix (`U_`, `C_`, `M_`, `H_`, `O_`, `T_`, `MT_`, `MC_`, `W_`, `WI_`).
- Derived the canonical cover (17 functional dependencies) directly from each entity's/
  relationship's own key and its `UNIQUE` constraints, checked minimality of the composite
  left-hand sides by example, and separately listed the functional dependencies that hold by
  foreign-key substitution (e.g. `M_CRYPTO_ID → C_SYMBOL, C_NAME, C_CREATED_AT`) without
  folding them into the canonical cover, since they are derivable rather than independent.
- Computed the candidate keys of `R_EDUBERZA` from first principles: since `Holds`,
  `Contains`, `Orders`, `Transactions`, `MarketTrades`, `MarketCandles` and `Watchlists` are
  independent of each other, the only candidate keys are combinations that pick one
  identifying attribute set per cluster — 96 in total — and selected the all-surrogate-key
  combination as primary key, with a full closure computation shown step by step.
- Decomposed `R_EDUBERZA` using 3NF/BCNF **synthesis** on the canonical cover (rather than the
  binary decomposition algorithm), producing ten relations in one step, then separately
  verified 3NF (checking every foreign-key-carried transitive dependency by name and showing
  none of them lands inside any single resulting relation) and BCNF (a determinant/candidate-key
  table for all ten relations) as distinct, explicit checks per the phase template, even
  though no additional splitting was needed at either stage.
- Verified dependency preservation (every canonical-cover FD's determinant and dependents
  land inside exactly one resulting relation) and lossless join (every foreign key is
  equated to the primary key it references, the textbook sufficient condition) explicitly,
  rather than asserting them.
- Compared the result to [RelationalDesign](../P2-RelationalDesign/RelationalDesign.md) and
  found it identical relation-for-relation and key-for-key, including the less obvious
  composite candidate keys; documented the one real difference (`holdings.avg_price` is a
  derived/cached attribute — a property no single-relation normal form check can see) and
  concluded, with reasoning, that P2's design should continue to be used unchanged.
- Added a short cross-reference to this page from
  [RelationalDesign](../P2-RelationalDesign/RelationalDesign.md), since the phase instructions
  ask for Phase 2 documentation to be updated with the outcome of this phase.
- Wrote [Normalization](Normalization.md) following the section headings given in the phase
  template exactly (`De-normalized database form` → `Functional dependencies` →
  `Candidate keys and primary key` → `1NF decomposition` → `2NF decomposition` →
  `3NF decomposition` → `BCNF if possible` → `Final result and discussion`).

## Summary of AI involvement

| | This session — 2026-09-16 |
|---|---|
| **What I brought** | The phase rubric for P5, pasted in full, and everything already produced in P1–P4 (in particular the `reserved_quantity` addition to `Holds` from the previous session) |
| **What the AI did** | Built the de-normalized relation, derived the canonical cover, found the candidate keys, ran the 1NF→2NF→3NF→BCNF synthesis, and wrote the comparison against P2 |
| **What I decided** | To let the AI carry out the full formal derivation rather than write my own first pass, since the rubric's own advice ("start from the canonical cover") is a mechanical method rather than a matter of taste; to keep P2's schema unchanged, per the AI's reasoning that the two designs coincide exactly |

This phase's rule is that AI is used **to improve the student's own initial work**, and that
any idea taken from the AI is logged as a change against that starting point. I did not
produce an independent first attempt at the canonical cover or the decomposition before
asking for this — I gave the AI the rubric directly and asked it to carry out the phase, the
same way P1–P4 were produced (see
[ERModelAIUsage](../P1-ConceptualModel/ERModelAIUsage.md) for that history). What I own here
is checking the result: that the 68-attribute list in `R_EDUBERZA` really is every attribute
of my P1 model with nothing missing or invented, that the functional dependencies match what
I already know to be true of the model (each `UNIQUE` constraint in
[`schema_creation.sql`](../../server/db/schema_creation.sql) shows up as an alternate-key FD,
and no others were invented), and that the final ten relations really do match
[RelationalDesign](../P2-RelationalDesign/RelationalDesign.md) column for column — which I
checked by reading both side by side rather than taking the AI's claim of a match on faith.

## Entire AI usage log

### 2026-09-16

**Intent:** hand over the full P5 rubric and have the phase carried out end to end —
de-normalized relation, functional dependencies, candidate keys, the four-normal-form
decomposition, and the comparison against P2 — in one pass.

**Prompt (student, verbatim):**
> We will go phase by phase, here are the instructions for P5:
> Instructions on Phase P5: Normalization
> [the full task description was pasted: parts (a) initial de-normalized relation and
> functional dependencies, (b) candidate keys and primary key selection, (c) step-by-step
> decomposition to the highest possible normal form with the specific checklist of what each
> decomposition step must document, (d) final result and discussion including updating Phase
> 2 documentation and restructuring the database if warranted; the exact wiki page template
> for `Normalization` and `NormalizationAIUsage`; and the phase's AI-use rules]

**Response (AI, summarised):**
- Re-read [ERModel](../P1-ConceptualModel/ERModel.md) and
  [`schema_creation.sql`](../../server/db/schema_creation.sql) to get the authoritative,
  current attribute list (including `reserved_quantity`, added in the previous session) and
  every `UNIQUE`/`CHECK` constraint that turns into an alternate-key functional dependency.
- Worked out, before writing anything, that `Holds`/`Contains`/`Orders`/`Transactions`/
  `MarketTrades`/`MarketCandles`/`Watchlists` are mutually independent record types, which is
  what makes the primary key of the fully de-normalized relation a ten-attribute composite
  rather than something smaller — and therefore what makes *every* non-key attribute violate
  2NF simultaneously, rather than a handful needing to be peeled off one at a time.
- Chose synthesis over the binary decomposition algorithm specifically because the rubric
  recommends building the canonical cover first, which is what synthesis consumes directly.
- Wrote [Normalization.md](Normalization.md) and this page.

**What I decided:** to accept the derivation as presented rather than rework it, since
checking it against my own P1/P2 documents (attribute list, `UNIQUE` constraints, and the
final ten relations) confirmed it, and to make no changes to `server/db/schema_creation.sql`
for this phase, since the discussion section's conclusion — that P2's design is already the
BCNF result — is one I verified myself rather than took on trust.

> **Student action required.** Read [Normalization.md](Normalization.md) end to end before
> the defense — you will be expected to derive at least one of the ten relations' functional
> dependencies and candidate keys live, and to explain why `holdings.avg_price` is not a
> normal-form violation even though it is a stored, derivable value. Append any further
> prompts here if you ask for revisions.
