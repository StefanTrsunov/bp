# Normalization

This phase does not use the relations of
[RelationalDesign](../P2-RelationalDesign/RelationalDesign.md) (P2) as a starting point.
It starts from the attributes of [ERModel](../P1-ConceptualModel/ERModel.md) **v05** (P1),
put into one de-normalized relation. It states the functional dependencies that the
model's rules impose on those attributes, **computes** the keys of that relation from the
dependencies, and then decomposes it step by step through 2NF, 3NF and BCNF. Every step is
checked for a lossless join and for dependency preservation. The
[final section](#final-result-and-discussion) compares the result with P2.

## De-normalized database form

### Which attributes go into the relation

The relation contains **the attributes of the ER model and nothing else**. In v05 all
attributes belong to the 11 entity sets. None of the 15 relationships has attributes of its
own.

A relationship adds **no column**. Foreign-key columns such as `crypto_id` or `watchlist_id`
belong to the relational model of P2, not to the ER model, so they do not appear here. What a
relationship contributes is a **functional dependency** between attributes that are already
in the relation. For example, `Contains` (Watchlists 1 : N WatchlistItems) says that every
watchlist item is on exactly one watchlist, which is the dependency `WI_ID → W_ID` in the
next section. It is not a column `WI_WATCHLIST_ID`.

Attribute names are prefixed with the entity set they come from, because several names repeat
across the model (`id`, `created_at`, `quantity`, `type`, `name`, `price`, `side`), and one
relation cannot contain the same name twice.

| Prefix | Entity set (P1) | Attributes |
|---|---|---|
| `U_`  | Users          | `U_ID, U_USERNAME, U_EMAIL, U_FULL_NAME, U_PASSWORD_HASH, U_AVAILABLE_BALANCE, U_INVESTED_BALANCE, U_RESERVED_BALANCE, U_CREATED_AT, U_UPDATED_AT` |
| `C_`  | Cryptos        | `C_ID, C_SYMBOL, C_NAME, C_CREATED_AT` |
| `M_`  | Markets        | `M_ID, M_QUOTE_CURRENCY, M_IS_ACTIVE, M_CREATED_AT` |
| `H_`  | Holdings       | `H_ID, H_QUANTITY, H_RESERVED_QUANTITY, H_AVG_PRICE, H_CREATED_AT, H_UPDATED_AT` |
| `O_`  | Orders         | `O_ID, O_SIDE, O_TYPE, O_STATUS, O_QUANTITY, O_FILLED_QUANTITY, O_PRICE, O_PLACED_AT, O_EXECUTED_AT` |
| `T_`  | Transactions   | `T_ID, T_TYPE, T_AMOUNT, T_CURRENCY, T_CREATED_AT, T_DESCRIPTION` |
| `MT_` | MarketTrades   | `MT_ID, MT_EXECUTED_AT, MT_PRICE, MT_QUANTITY, MT_SIDE, MT_SOURCE` |
| `OE_` | OrderEvents    | `OE_ID, OE_EVENT_TYPE, OE_QUANTITY, OE_PRICE, OE_STATUS_AFTER, OE_CREATED_AT` |
| `MC_` | MarketCandles  | `MC_ID, MC_TIMEFRAME, MC_OPEN, MC_HIGH, MC_LOW, MC_CLOSE, MC_VOLUME, MC_CANDLE_TIME` |
| `W_`  | Watchlists     | `W_ID, W_NAME, W_CREATED_AT` |
| `WI_` | WatchlistItems | `WI_ID, WI_ADDED_AT` |

That is 64 attributes. **One case needs two more.** `FillsBuy` and `FillsSell` are two
different relationships between the same two entity sets, Orders and MarketTrades. A trade
can fill one buy order *and* one sell order, which are two different orders. One relation
has only one `O_ID` column, and one column cannot hold two different orders in the same
tuple. So the order's identifier appears once per **role**, named after the relationship
that gives the role:

| Attribute | Meaning |
|---|---|
| `O_ID_FILLSBUY`  | the `id` of Orders, in its role in `FillsBuy` (the buy order a trade filled) |
| `O_ID_FILLSSELL` | the `id` of Orders, in its role in `FillsSell` (the sell order a trade filled) |

These are not foreign keys copied from P2. They are the ER attribute `Orders.id` itself, once
for each of the two relationships. [ERModel](../P1-ConceptualModel/ERModel.md) names these two
roles of `Orders` explicitly: *the buy order* of a trade in `FillsBuy`, and *the sell order* in
`FillsSell`. This is the only place where the model has two
relationships between the same pair of entity sets. Every other relationship is expressed with
the attributes above, without renaming.

This gives **one relation, `R_EDUBERZA`, of 66 attributes:**

```
R_EDUBERZA(
  U_ID, U_USERNAME, U_EMAIL, U_FULL_NAME, U_PASSWORD_HASH, U_AVAILABLE_BALANCE,
  U_INVESTED_BALANCE, U_RESERVED_BALANCE, U_CREATED_AT, U_UPDATED_AT,
  C_ID, C_SYMBOL, C_NAME, C_CREATED_AT,
  M_ID, M_QUOTE_CURRENCY, M_IS_ACTIVE, M_CREATED_AT,
  H_ID, H_QUANTITY, H_RESERVED_QUANTITY, H_AVG_PRICE, H_CREATED_AT, H_UPDATED_AT,
  O_ID, O_SIDE, O_TYPE, O_STATUS, O_QUANTITY, O_FILLED_QUANTITY, O_PRICE,
  O_PLACED_AT, O_EXECUTED_AT,
  T_ID, T_TYPE, T_AMOUNT, T_CURRENCY, T_CREATED_AT, T_DESCRIPTION,
  MT_ID, MT_EXECUTED_AT, MT_PRICE, MT_QUANTITY, MT_SIDE, MT_SOURCE,
  O_ID_FILLSBUY, O_ID_FILLSSELL,
  OE_ID, OE_EVENT_TYPE, OE_QUANTITY, OE_PRICE, OE_STATUS_AFTER, OE_CREATED_AT,
  MC_ID, MC_TIMEFRAME, MC_OPEN, MC_HIGH, MC_LOW, MC_CLOSE, MC_VOLUME, MC_CANDLE_TIME,
  W_ID, W_NAME, W_CREATED_AT,
  WI_ID, WI_ADDED_AT
)
```

To keep the tables below readable, **`X_*`** means the non-identifier attributes of prefix
`X_`. For example, `U_*` = `U_USERNAME … U_UPDATED_AT` (9 attributes), and `O_*` =
`O_SIDE … O_EXECUTED_AT` (8 attributes). `U_ID`, `O_ID`, … are always written out.

Every attribute is single-valued and atomic (a balance, a timestamp, a symbol, an amount —
nothing here is a list or a nested record), so `R_EDUBERZA` satisfies 1NF as soon as it is
written down.

## Functional dependencies

At this point `R_EDUBERZA` is just a set of attributes. It has **no keys yet**. `U_ID`,
`O_ID`, … are ordinary attributes of this relation, and which attribute sets are keys of
`R_EDUBERZA` is computed in the [next section](#candidate-keys-and-primary-key), from the
dependencies below. Each dependency is justified by a rule of the domain, as described in
the data requirements of [ERModel](../P1-ConceptualModel/ERModel.md). The rules are of four
kinds:

- **(I) Identification.** Every value of an identifier (`U_ID`, `C_ID`, …) is given to
  exactly one real object: one user, one crypto, one order. That object has exactly one
  username, one balance, one price, and so on. So the identifier's value fixes those values.
- **(R) 1:N relationship.** In a 1:N relationship, each object on the N side is linked to
  exactly one object on the 1 side. So the N side's identifier fixes the 1 side's
  identifier. Example: an order is placed by exactly one user (`Places`), so `O_ID → U_ID`.
  The opposite direction does not hold: a user places many orders, so `U_ID ↛ O_ID`.
- **(U) Uniqueness rule.** A rule of the form "at most one X per Y and Z" gives
  `Y, Z → X`.
- **(N) Unique natural attribute.** No two users share a username or an email, and no two
  cryptos share a symbol.

**Only rules of the ER model are used.** The dependencies below come from the rules stated in
[ERModel](../P1-ConceptualModel/ERModel.md) v05 and nothing else. The analysis uses the
classical definitions (Armstrong's axioms), with no special treatment of `NULL`. Partial
relationships (`Settles`, `FillsBuy`, `FillsSell`) are discussed where they matter:
under [Canonical cover](#canonical-cover) and in the [discussion](#discussion).

| # | Functional dependency | Rule | Why it holds |
|---|---|---|---|
| FD1  | `U_ID → U_USERNAME, U_EMAIL, U_FULL_NAME, U_PASSWORD_HASH, U_AVAILABLE_BALANCE, U_INVESTED_BALANCE, U_RESERVED_BALANCE, U_CREATED_AT, U_UPDATED_AT` | I | one user, one value of each |
| FD2  | `U_USERNAME → U_ID` | N | usernames are unique |
| FD3  | `U_EMAIL → U_ID` | N | emails are unique |
| FD4  | `C_ID → C_SYMBOL, C_NAME, C_CREATED_AT` | I | one crypto, one value of each |
| FD5  | `C_SYMBOL → C_ID` | N | symbols are unique |
| FD6  | `M_ID → M_QUOTE_CURRENCY, M_IS_ACTIVE, M_CREATED_AT, C_ID` | I, R | …and a market is `QuotedOn` exactly one crypto |
| FD7  | `C_ID, M_QUOTE_CURRENCY → M_ID` | U | a crypto is quoted at most once per currency |
| FD8  | `H_ID → H_QUANTITY, H_RESERVED_QUANTITY, H_AVG_PRICE, H_CREATED_AT, H_UPDATED_AT, U_ID, C_ID` | I, R | …and a holding belongs to one user (`Holds`) and is a position in one crypto (`PositionIn`) |
| FD9  | `U_ID, C_ID → H_ID` | U | at most one holding per user and crypto |
| FD10 | `O_ID → O_SIDE, O_TYPE, O_STATUS, O_QUANTITY, O_FILLED_QUANTITY, O_PRICE, O_PLACED_AT, O_EXECUTED_AT, U_ID, M_ID` | I, R | …and an order is placed by one user (`Places`) on one market (`PlacedOn`) |
| FD11 | `T_ID → T_TYPE, T_AMOUNT, T_CURRENCY, T_CREATED_AT, T_DESCRIPTION, U_ID, O_ID` | I, R | …and a ledger entry belongs to one user (`Records`) and to at most one order (`Settles`) |
| FD12 | `MT_ID → MT_EXECUTED_AT, MT_PRICE, MT_QUANTITY, MT_SIDE, MT_SOURCE, M_ID, O_ID_FILLSBUY, O_ID_FILLSSELL` | I, R | …and a trade happened on one market (`Fills`) and filled at most one buy order (`FillsBuy`) and at most one sell order (`FillsSell`) |
| FD13 | `OE_ID → OE_EVENT_TYPE, OE_QUANTITY, OE_PRICE, OE_STATUS_AFTER, OE_CREATED_AT, O_ID` | I, R | …and an event belongs to one order (`Logs`) |
| FD14 | `MC_ID → MC_TIMEFRAME, MC_OPEN, MC_HIGH, MC_LOW, MC_CLOSE, MC_VOLUME, MC_CANDLE_TIME, M_ID` | I, R | …and a candle summarises one market (`Aggregates`) |
| FD15 | `M_ID, MC_TIMEFRAME, MC_CANDLE_TIME → MC_ID` | U | one candle per market, timeframe and bucket |
| FD16 | `W_ID → W_NAME, W_CREATED_AT, U_ID` | I, R | …and a watchlist is owned by one user (`Owns`) |
| FD17 | `WI_ID → WI_ADDED_AT, W_ID, C_ID` | I, R | …and an item is on one watchlist (`Contains`) and names one crypto (`Lists`) |
| FD18 | `W_ID, C_ID → WI_ID` | U | an asset appears at most once per watchlist |

**Dependencies that do *not* hold** are as important, because they are why some attributes
must be combined in the key later:

- The reverse of every (R) dependency, e.g. `U_ID ↛ O_ID`, `M_ID ↛ MT_ID`, `W_ID ↛ WI_ID`.
  These are 1:N, not 1:1.
- `M_ID, MT_EXECUTED_AT ↛ MT_ID`. Two trades on a market can share a timestamp.
- `U_ID, W_NAME ↛ W_ID`. The model does not require list names to be unique per user.
- `O_ID_FILLSBUY` and `O_ID_FILLSSELL` determine no other attribute of `R_EDUBERZA` **by any
  rule of the ER model**. The order data (`O_SIDE`, `O_PRICE`, …) describes the order in the
  `O_ID` column, not the order in a role column. (The database also has a rule that a trade
  and the orders it fills are on the same market. That rule is a trigger in P7 relating
  several entity sets, not a rule of the ER model, so it is not used here.)

### Canonical cover

A canonical (minimal) cover is obtained in three steps.

**Step 1 — single attribute on the right.** Each FD above is read as one dependency per
right-side attribute, e.g. FD6 is `M_ID → M_QUOTE_CURRENCY`, `M_ID → M_IS_ACTIVE`,
`M_ID → M_CREATED_AT`, `M_ID → C_ID`.

**Step 2 — no extraneous attribute on the left.** Only FD7, FD9, FD15 and FD18 have more than one
attribute on the left. For each one, dropping any attribute makes the rule false:

| FD | Drop | Counter-example (the smaller left side does not determine the right side) |
|---|---|---|
| FD7  | `M_QUOTE_CURRENCY` | BTC is quoted in USD *and* in EUR: one `C_ID`, two markets |
|      | `C_ID` | USD is the quote currency of many markets |
| FD9  | `C_ID` | one user holds several cryptos |
|      | `U_ID` | one crypto is held by several users |
| FD15 | `M_ID` | every market has a `1h` candle starting at 10:00 |
|      | `MC_TIMEFRAME` | a market has a `1m` and a `1h` candle both starting at 10:00 |
|      | `MC_CANDLE_TIME` | a market has many `1h` candles |
| FD18 | `C_ID` | a watchlist has several items |
|      | `W_ID` | a crypto is on several watchlists |

**Step 3 — no redundant dependency.** A dependency is redundant if it follows from the others. For
almost every dependency, its right-side attribute appears on the right of no other
dependency with a different left side (e.g. nothing but `U_ID` determines
`U_AVAILABLE_BALANCE`), so it cannot be derived. The candidates worth checking are the
identifiers that are reached from several places:

- **`T_ID → U_ID` is redundant.** It follows by transitivity from `T_ID → O_ID` (FD11) and
  `O_ID → U_ID` (FD10): a ledger entry's user is the user of the order it settles. It is
  therefore **removed** from FD11. The derivation is valid only for an entry that has an
  order. Every tuple of `R_EDUBERZA` does have one (see the
  [discussion](#discussion)), so in the de-normalized relation the removal is correct. The
  consequence for deposits, which have no order, is taken up in the discussion.
- `H_ID → U_ID`, `H_ID → C_ID`, `WI_ID → W_ID`, `WI_ID → C_ID`, `M_ID → C_ID`, `MT_ID → M_ID`,
  `MC_ID → M_ID`, `OE_ID → O_ID`, `W_ID → U_ID` and `O_ID → U_ID`, `O_ID → M_ID`: for
  each, no other dependency with a different left side has that attribute on its right
  side and a left side reachable from this one, so none can be derived.
- The four (U) and three (N) dependencies go "backwards" from a non-identifier to an
  identifier. Nothing else produces an identifier from those attributes, so they are not
  derivable either.

Grouping the single-attribute dependencies back by left side gives FD1–FD18 as listed,
except that FD11 loses `U_ID`:

| # | Functional dependency (canonical cover) |
|---|---|
| FD11 | `T_ID → T_TYPE, T_AMOUNT, T_CURRENCY, T_CREATED_AT, T_DESCRIPTION, O_ID` |

**FD1–FD18, with this FD11, is the canonical cover.** From here on, "FD11" means this reduced
form.

## Candidate keys and primary key

A candidate key is a minimal set of attributes whose closure under FD1–FD18 is all 66
attributes.

**Attributes that must be in every key.** `T_ID`, `OE_ID` and `MT_ID` appear on the right side
of no dependency. Nothing determines them, so every key must contain them.

**Closure of `{T_ID, OE_ID, MT_ID}`:**

| Step | Added | Using |
|---|---|---|
| start | `T_ID, OE_ID, MT_ID` | — |
| 1 | `T_*`, `O_ID` | FD11 |
| 2 | `OE_*` | FD13 |
| 3 | `MT_*`, `M_ID`, `O_ID_FILLSBUY`, `O_ID_FILLSSELL` | FD12 |
| 4 | `O_*`, `U_ID` | FD10 |
| 5 | `U_*` | FD1 |
| 6 | `M_*`, `C_ID` | FD6 |
| 7 | `C_*` | FD4 |
| 8 | `H_ID` | FD9 (`U_ID` and `C_ID` are both present) |
| 9 | `H_*` | FD8 |

That is 53 attributes. Still missing are all 8 `MC_` attributes, the 3 `W_` attributes and
the 2 `WI_` attributes:

- **`MC_`:** only `MC_ID` determines them (FD14), and `MC_ID` is reached only by FD15, which
  needs `M_ID` (already present), `MC_TIMEFRAME` and `MC_CANDLE_TIME`. So the key must add
  either `MC_ID` or both `MC_TIMEFRAME` and `MC_CANDLE_TIME`. Neither of those two alone is
  enough.
- **`W_` and `WI_`:** `WI_ID` gives `W_ID` (FD17), and `W_ID` gives `WI_ID` together with
  `C_ID`, which is already present (FD18). So adding either `WI_ID` or `W_ID` gives all five.

**Candidate keys** (each one's closure is all 66 attributes, and removing any member breaks
that, by the argument above):

| Key | Attributes |
|---|---|
| **K1** | `T_ID, OE_ID, MT_ID, MC_ID, WI_ID` |
| K2 | `T_ID, OE_ID, MT_ID, MC_ID, W_ID` |
| K3 | `T_ID, OE_ID, MT_ID, MC_TIMEFRAME, MC_CANDLE_TIME, WI_ID` |
| K4 | `T_ID, OE_ID, MT_ID, MC_TIMEFRAME, MC_CANDLE_TIME, W_ID` |

**Primary key: K1.** It consists only of identifiers, and it is the key that remains at the
end of the decomposition below.

**Prime attributes** (in at least one candidate key): `T_ID, OE_ID, MT_ID, MC_ID,
MC_TIMEFRAME, MC_CANDLE_TIME, W_ID, WI_ID`. The other 58 attributes are **non-prime**. The
difference matters: 2NF and 3NF only restrict dependencies of non-prime attributes, and BCNF
restricts all of them.

In words, a tuple of `R_EDUBERZA` puts together one ledger entry, one order event, one
trade, one candle and one watchlist item. Everything else in the tuple (the user, the order,
the market, the crypto, the holding, the watchlist) follows from those five.

**Normal form of `R_EDUBERZA`:** 1NF only. It is not in 2NF, because, for example, `T_AMOUNT`
depends on `T_ID` alone, a proper part of K1.

## 1NF decomposition

No decomposition is needed. Every attribute of `R_EDUBERZA` is atomic and single-valued, and
the relation has no repeating groups (see
[De-normalized database form](#de-normalized-database-form)).

## 2NF decomposition

### How every step is described and checked

Each step of 2NF, 3NF and BCNF below lists, in this order: the relation analyzed, its
dependencies, its candidate keys and primary key, and its normal form; the dependency that
violates the next normal form and is used for the split; the two resulting relations, each
with its dependencies, keys and normal form; and the dependency-preservation and lossless-join
checks.

Every step splits one relation `R` into two: the **extracted** relation `Ri` and the
**residual** relation `R'` (what is left of `R`). The same two checks are made each time:

- **Lossless join.** The split of `R` into `Ri` and `R'` is lossless if the common attributes
  determine one of the two sides: `(Ri ∩ R') → Ri` or `(Ri ∩ R') → R'`. Every step below
  extracts `Ri = X ∪ (what X determines)` for some determinant `X` that stays in `R'`. So
  `X ⊆ Ri ∩ R'` and `X → Ri`, and the first condition holds.
- **Dependency preservation.** Every dependency of the canonical cover must end up with all
  its attributes inside one relation. So an attribute is removed from the residual only when
  no dependency still waiting in the residual needs it. Otherwise it is extracted **and**
  kept.

**Relation analyzed first:** `R_EDUBERZA` (66 attributes), dependencies FD1–FD18, candidate
keys K1–K4, primary key K1. **Normal form:** 1NF.

**Dependencies that violate 2NF.** 2NF forbids a non-prime attribute from depending on a proper
part of a candidate key. There are six such partial dependencies:

| Part of a key | Non-prime attributes that depend on it | Through |
|---|---|---|
| `T_ID` (K1–K4)  | `T_*`, `O_ID`, and through them `O_*`, `U_ID`, `U_*`, `M_ID`, `M_*`, `C_ID`, `C_*`, `H_ID`, `H_*` | FD11, then FD10, FD1, FD6, FD4, FD9, FD8 |
| `OE_ID` (K1–K4) | `OE_*`, `O_ID` | FD13 |
| `MT_ID` (K1–K4) | `MT_*`, `M_ID`, `O_ID_FILLSBUY`, `O_ID_FILLSSELL` | FD12 |
| `MC_ID` (K1, K2) | `MC_OPEN, MC_HIGH, MC_LOW, MC_CLOSE, MC_VOLUME`, `M_ID` | FD14 |
| `W_ID` (K2, K4) | `W_*`, `U_ID` | FD16 |
| `WI_ID` (K1, K3) | `WI_ADDED_AT`, `C_ID` | FD17 |

The table lists the part of a key that each group depends on most directly. It is not the
only one: under K3/K4, for example, `MC_OPEN … MC_VOLUME` also depend on
`{MT_ID, MC_TIMEFRAME, MC_CANDLE_TIME}`, and under K1/K3 `W_*` depend on `WI_ID` through
`W_ID`. These lead to the same relations, so they need no extra steps. `MC_TIMEFRAME`,
`MC_CANDLE_TIME` and `W_ID` also depend on parts of keys, but they are prime, so 2NF does not
restrict them. They are handled under BCNF.

Each step below removes one row of this table, splitting the current relation into two. The
**order** is chosen so that no dependency is lost. `T_ID` goes first, because its group is the
largest and carries FD1–FD11 with it. Each later step handles a group whose determinant is
still in the residual relation.

### Step 2NF-1 — partial dependency on `T_ID`

- **Relation analyzed:** `R_EDUBERZA` (66 attributes).
- **Dependencies:** FD1–FD18. **Candidate keys:** K1–K4. **Primary key:** K1.
  **Normal form:** 1NF.
- **2NF violations:** all six rows of the table above. **Split first on `T_ID`**, the
  largest group (see the order explained above).
- **Decomposition dependency:** `T_ID → T_*, O_ID` (FD11), together with everything it
  determines transitively (FD10, FD1, FD6, FD4, FD9, FD8). `T_ID` is a proper part of K1, and
  `T_AMOUNT`, for example, is non-prime, so this violates 2NF.
- **New relation `R_A`** = `{ T_ID, T_*, O_ID, O_*, U_ID, U_*, M_ID, M_*, C_ID, C_*, H_ID, H_* }`
  (39 attributes). Dependencies: FD1–FD11. Candidate key and primary key: `T_ID`. Normal form: 2NF (it has a
  one-attribute key), but not 3NF (see 3NF).
- **Residual relation `S1`** = `R_EDUBERZA − { T_*, O_*, U_*, M_*, C_*, H_ID, H_* }` =
  `{ T_ID, O_ID, U_ID, M_ID, C_ID, OE_ID, OE_*, MT_ID, MT_*, O_ID_FILLSBUY, O_ID_FILLSSELL,
  MC_ID, MC_*, W_ID, W_*, WI_ID, WI_ADDED_AT }` (32 attributes). `O_ID`, `U_ID`, `M_ID` and
  `C_ID` stay, because FD13, FD16, FD12/FD14/FD15 and FD17/FD18 still need them. Dependencies: FD12–FD18, plus the projected dependencies between the identifiers kept here:
  `T_ID → O_ID, U_ID, M_ID, C_ID`, `O_ID → U_ID, M_ID, C_ID`, `M_ID → C_ID`,
  `OE_ID → U_ID, M_ID, C_ID`, `MT_ID → C_ID`, `MC_ID → C_ID`, `WI_ID → U_ID`.
  Candidate keys: K1–K4 (all
  their attributes are still here). Normal form: 1NF.
- **Dependency preservation:** FD1–FD11 lie entirely in `R_A`, and FD12–FD18 entirely in `S1`. ✓
- **Lossless join:** `R_A ∩ S1 = { T_ID, O_ID, U_ID, M_ID, C_ID }` contains `T_ID`, and
  `T_ID → R_A`, so `(R_A ∩ S1) → R_A`. ✓

### Step 2NF-2 — partial dependency on `OE_ID`

- **Relation analyzed:** `S1` (32 attributes). Dependencies: as listed for `S1` in the
  previous step. Candidate keys: K1–K4. Primary key: K1. Normal form: 1NF.
- **Remaining 2NF violations:** the partial dependencies on `OE_ID`, `MT_ID`, `MC_ID`, `W_ID`
  and `WI_ID` (table above), and the partial dependencies of the kept identifiers
  `O_ID`, `U_ID`, `M_ID`, `C_ID` on `T_ID`. The kept identifiers cannot leave yet, because
  other groups still need them. Each one leaves with the last group that needs it (`O_ID` in
  2NF-2, `M_ID` in 2NF-4, `U_ID` in 2NF-5, `C_ID` in 2NF-6). **Split first on `OE_ID`**,
  because after it no group needs `O_ID` any more.
- **Decomposition dependency:** `OE_ID → OE_*, O_ID` (FD13). `OE_ID` is a proper part of K1
  and `OE_*` are non-prime.
- **New relation `R_B`** = `{ OE_ID, OE_*, O_ID }` (7 attributes). Dependencies: FD13.
  Candidate key: `OE_ID`. Normal form: BCNF.
- **Residual relation `S2`** = `S1 − { OE_*, O_ID }` (26 attributes). No dependency still
  needed in the residual uses `O_ID`. Dependencies: FD12, FD14–FD18, plus the projected `T_ID → U_ID, M_ID, C_ID`,
  `OE_ID → U_ID, M_ID, C_ID`, `M_ID → C_ID`, `MT_ID → C_ID`, `MC_ID → C_ID`, `WI_ID → U_ID`.
  Candidate keys: K1–K4. Normal form: 1NF.
- **Dependency preservation:** FD13 is in `R_B`, and the others are in `S2`.
  `T_ID → O_ID` is already kept in `R_A`. ✓
- **Lossless join:** `R_B ∩ S2 = { OE_ID }`, and `OE_ID → R_B` (FD13). ✓

### Step 2NF-3 — partial dependency on `MT_ID`

- **Relation analyzed:** `S2` (26 attributes). Dependencies: as listed for `S2` in the
  previous step. Candidate keys: K1–K4. Primary key: K1. Normal form: 1NF.
- **Remaining 2NF violations:** the groups of `MT_ID`, `MC_ID`, `W_ID`, `WI_ID`, and the kept
  identifiers `U_ID`, `M_ID`, `C_ID`. **Split first on `MT_ID`**, the next group. `M_ID` must
  still stay for `MC_ID`.
- **Decomposition dependency:** `MT_ID → MT_*, M_ID, O_ID_FILLSBUY, O_ID_FILLSSELL` (FD12).
- **New relation `R_C`** = `{ MT_ID, MT_*, M_ID, O_ID_FILLSBUY, O_ID_FILLSSELL }`
  (9 attributes). Dependencies: FD12. Candidate key: `MT_ID`. Normal form: BCNF.
- **Residual relation `S3`** = `S2 − { MT_*, O_ID_FILLSBUY, O_ID_FILLSSELL }` (19 attributes).
  `M_ID` stays, because FD14/FD15 need it. Dependencies: FD14–FD18, plus the projected `T_ID → U_ID, M_ID, C_ID`,
  `OE_ID → U_ID, M_ID, C_ID`, `MT_ID → M_ID, C_ID`, `M_ID → C_ID`, `MC_ID → C_ID`,
  `WI_ID → U_ID`.
  Candidate keys: K1–K4. Normal form: 1NF.
- **Dependency preservation:** FD12 is in `R_C`, and FD14–FD18 are in `S3`. ✓
- **Lossless join:** `R_C ∩ S3 = { MT_ID, M_ID }` contains `MT_ID`, and `MT_ID → R_C`
  (FD12). ✓

### Step 2NF-4 — partial dependency on `MC_ID`

- **Relation analyzed:** `S3` (19 attributes). Dependencies: as listed for `S3` in the
  previous step. Candidate keys: K1–K4. Primary key: K1. Normal form: 1NF.
- **Remaining 2NF violations:** the groups of `MC_ID`, `W_ID`, `WI_ID`, and the kept
  identifiers `U_ID`, `M_ID`, `C_ID`. **Split first on `MC_ID`**, the last group that needs
  `M_ID`, so `M_ID` can leave with it.
- **Decomposition dependency:** `MC_ID → MC_OPEN, MC_HIGH, MC_LOW, MC_CLOSE, MC_VOLUME, M_ID`
  (FD14). `MC_ID` is a proper part of K1. The prime `MC_TIMEFRAME` and `MC_CANDLE_TIME` also go
  into the new relation, so that FD15, which needs them with `M_ID` and `MC_ID`, is preserved.
- **New relation `R_D`** = `{ MC_ID, MC_TIMEFRAME, MC_OPEN, MC_HIGH, MC_LOW, MC_CLOSE,
  MC_VOLUME, MC_CANDLE_TIME, M_ID }` (9 attributes). Dependencies: FD14, FD15. Candidate keys:
  `MC_ID` and `{M_ID, MC_TIMEFRAME, MC_CANDLE_TIME}`. Normal form: BCNF.
- **Residual relation `S4`** = `S3 − { MC_OPEN, MC_HIGH, MC_LOW, MC_CLOSE, MC_VOLUME, M_ID }`
  (13 attributes). `MC_TIMEFRAME` and `MC_CANDLE_TIME` are prime and stay. Dependencies: FD16–FD18, plus the projected `T_ID → U_ID, C_ID`, `OE_ID → U_ID, C_ID`,
  `MT_ID → C_ID`, `MC_ID → MC_TIMEFRAME, MC_CANDLE_TIME, C_ID`, `WI_ID → U_ID`.
  Candidate keys: K1–K4. Normal form: 1NF.
- **Dependency preservation:** FD14 and FD15 are in `R_D`, and FD16–FD18 are in `S4`. ✓
- **Lossless join:** `R_D ∩ S4 = { MC_ID, MC_TIMEFRAME, MC_CANDLE_TIME }` contains `MC_ID`,
  and `MC_ID → R_D` (FD14). ✓

### Step 2NF-5 — partial dependency on `W_ID`

- **Relation analyzed:** `S4` (13 attributes). Dependencies: as listed for `S4` in the
  previous step. Candidate keys: K1–K4. Primary key: K1. Normal form: 1NF.
- **Remaining 2NF violations:** the groups of `W_ID` and `WI_ID`, and the kept identifiers
  `U_ID`, `C_ID`. **Split first on `W_ID`**, the last group that needs `U_ID`.
- **Decomposition dependency:** `W_ID → W_NAME, W_CREATED_AT, U_ID` (FD16). `W_ID` is a proper
  part of K2.
- **New relation `R_E`** = `{ W_ID, W_NAME, W_CREATED_AT, U_ID }` (4 attributes). Dependencies:
  FD16. Candidate key: `W_ID`. Normal form: BCNF.
- **Residual relation `S5`** = `S4 − { W_NAME, W_CREATED_AT, U_ID }` (10 attributes).
  Dependencies: FD17, FD18, plus the projected `T_ID → C_ID`, `OE_ID → C_ID`, `MT_ID → C_ID`,
  `MC_ID → MC_TIMEFRAME, MC_CANDLE_TIME, C_ID`.
  Candidate keys: K1–K4. Normal form: 1NF.
- **Dependency preservation:** FD16 is in `R_E`, and FD17 and FD18 are in `S5`. ✓
- **Lossless join:** `R_E ∩ S5 = { W_ID }`, and `W_ID → R_E` (FD16). ✓

### Step 2NF-6 — partial dependency on `WI_ID`

- **Relation analyzed:** `S5` (10 attributes). Dependencies: as listed for `S5` in the
  previous step. Candidate keys: K1–K4. Primary key: K1. Normal form: 1NF.
- **Remaining 2NF violations:** the group of `WI_ID`, and the kept identifier `C_ID`.
  **Split on `WI_ID`**, the last group that needs `C_ID`.
- **Decomposition dependency:** `WI_ID → WI_ADDED_AT, W_ID, C_ID` (FD17). `WI_ID` is a proper
  part of K1, and `WI_ADDED_AT` and `C_ID` are non-prime.
- **New relation `R_F`** = `{ WI_ID, WI_ADDED_AT, W_ID, C_ID }` (4 attributes). Dependencies:
  FD17, FD18. Candidate keys: `WI_ID` and `{W_ID, C_ID}`. Normal form: BCNF.
- **Residual relation `S6`** = `S5 − { WI_ADDED_AT, C_ID }` =
  `{ T_ID, OE_ID, MT_ID, MC_ID, MC_TIMEFRAME, MC_CANDLE_TIME, W_ID, WI_ID }` (8 attributes).
  `W_ID` is prime and stays. Dependencies: no dependency of the cover lies entirely inside
  `S6`. The projected ones are `MC_ID → MC_TIMEFRAME, MC_CANDLE_TIME` and `WI_ID → W_ID`, plus
  derived ones such as `MT_ID, MC_TIMEFRAME, MC_CANDLE_TIME → MC_ID` and `MT_ID, W_ID → WI_ID`.
  Candidate keys: K1–K4. Normal form: 3NF, because every attribute is prime (and so 2NF).
- **Dependency preservation:** FD17 and FD18 are in `R_F`. ✓
- **Lossless join:** `R_F ∩ S6 = { WI_ID, W_ID }` contains `WI_ID`, and `WI_ID → R_F`
  (FD17). ✓

**Result of 2NF:** `R_A`, `R_B`, `R_C`, `R_D`, `R_E`, `R_F`, `S6`. All seven are in 2NF (`R_A`
only 2NF, `S6` 3NF, the rest BCNF). All 18 dependencies are preserved: FD1–FD11 in `R_A`,
FD13 in `R_B`, FD12 in `R_C`, FD14–FD15 in `R_D`, FD16 in `R_E`, FD17–FD18 in `R_F`.

## 3NF decomposition

Only `R_A` is not in 3NF. `R_B`–`R_F` are already in BCNF, and `S6` is in 3NF (all its
attributes are prime).

**Dependencies that violate 3NF in `R_A`.** 3NF forbids a non-prime attribute from depending on
a key only **transitively**, through a determinant that is not a superkey. The only key of
`R_A` is `T_ID`, but inside `R_A`:

- `U_ID → U_*` (FD1), `U_USERNAME → U_ID` (FD2), `U_EMAIL → U_ID` (FD3)
- `C_ID → C_*` (FD4), `C_SYMBOL → C_ID` (FD5)
- `U_ID, C_ID → H_ID` (FD9), `H_ID → H_*, U_ID, C_ID` (FD8)
- `M_ID → M_*, C_ID` (FD6), `C_ID, M_QUOTE_CURRENCY → M_ID` (FD7)
- `O_ID → O_*, U_ID, M_ID` (FD10)

None of these determinants is a superkey of `R_A`. For example, `T_ID → O_ID → O_PRICE` is a
transitive dependency of the non-prime `O_PRICE` on the key.

**Order of the steps.** An attribute can leave the residual only after every dependency that
needs it has been extracted. FD9 needs `U_ID` and `C_ID` together, and extracting `Markets`
takes `C_ID` out of the residual, so `Holdings` must come before `Markets`. Extracting
`Orders` takes `M_ID` and `U_ID` out, so `Orders` comes last. The dependencies are therefore
taken from the "leaves" of the chain `T_ID → O_ID → {U_ID, M_ID → C_ID}` inward.

### Step 3NF-1 — transitive dependency through `U_ID`

- **Relation analyzed:** `R_A` (39 attributes), dependencies FD1–FD11, candidate key and
  primary candidate key and primary key `T_ID`, normal form 2NF.
- **3NF violations:** all five groups listed above. **Split first on `U_ID`**. It is a leaf
  of the chain: its dependents determine nothing outside its own group.
- **Decomposition dependency:** `U_ID → U_*` (FD1). `U_ID` is not a superkey of `R_A`.
- **New relation `R_USERS`** = `{ U_ID, U_* }` (10 attributes). Dependencies: FD1, FD2, FD3.
  Candidate keys: `U_ID`, `U_USERNAME`, `U_EMAIL`. Primary key: `U_ID`. Normal form: BCNF.
- **Residual relation `R_A1`** = `R_A − U_*` (30 attributes). Dependencies: FD4–FD11, which
  also imply `T_ID → H_ID` and `O_ID → H_ID` (through `U_ID, C_ID`).
  Candidate key and primary key: `T_ID`. Normal form: 2NF.
- **Dependency preservation:** FD1–FD3 are in `R_USERS`, and FD4–FD11 are in `R_A1`. ✓
- **Lossless join:** `R_USERS ∩ R_A1 = { U_ID }`, and `U_ID → R_USERS` (FD1). ✓

### Step 3NF-2 — transitive dependency through `C_ID`

- **Relation analyzed:** `R_A1` (30 attributes), dependencies FD4–FD11, candidate key and primary key `T_ID`, normal form
  2NF.
- **3NF violations:** `C_ID → C_*`, `U_ID, C_ID → H_ID → H_*`, `M_ID → M_*, C_ID`,
  `O_ID → O_*, U_ID, M_ID`. **Split first on `C_ID`**, the next leaf.
- **Decomposition dependency:** `C_ID → C_*` (FD4).
- **New relation `R_CRYPTO`** = `{ C_ID, C_* }` (4 attributes). Dependencies: FD4, FD5.
  Candidate keys: `C_ID`, `C_SYMBOL`. Primary key: `C_ID`. Normal form: BCNF.
- **Residual relation `R_A2`** = `R_A1 − C_*` (27 attributes). Dependencies: FD6–FD11. Candidate
  key and primary key: `T_ID`. Normal form: 2NF.
- **Dependency preservation:** FD4 and FD5 are in `R_CRYPTO`, and FD6–FD11 are in `R_A2`. ✓
- **Lossless join:** `R_CRYPTO ∩ R_A2 = { C_ID }`, and `C_ID → R_CRYPTO` (FD4). ✓

### Step 3NF-3 — transitive dependency through `{U_ID, C_ID}`

- **Relation analyzed:** `R_A2` (27 attributes), dependencies FD6–FD11, candidate key and primary key `T_ID`, normal form
  2NF.
- **3NF violations:** `U_ID, C_ID → H_ID → H_*`, `M_ID → M_*, C_ID`, `O_ID → O_*, U_ID, M_ID`.
  **Split first on `{U_ID, C_ID}`**, because it must come before `Markets` takes `C_ID` away.
- **Decomposition dependency:** `U_ID, C_ID → H_ID` (FD9), together with `H_ID → H_*`
  (FD8).
- **New relation `R_HOLDINGS`** = `{ H_ID, H_*, U_ID, C_ID }` (8 attributes). Dependencies:
  FD8, FD9. Candidate keys: `H_ID`, `{U_ID, C_ID}`. Primary key: `H_ID`. Normal form: BCNF.
- **Residual relation `R_A3`** = `R_A2 − { H_ID, H_* }` (21 attributes). Dependencies: FD6,
  FD7, FD10, FD11. Candidate key and primary key: `T_ID`. Normal form: 2NF.
- **Dependency preservation:** FD8 and FD9 are in `R_HOLDINGS`, and the others are in `R_A3`. ✓
- **Lossless join:** `R_HOLDINGS ∩ R_A3 = { U_ID, C_ID }`, and `U_ID, C_ID → H_ID → H_*`, so
  `{U_ID, C_ID} → R_HOLDINGS`. ✓

### Step 3NF-4 — transitive dependency through `M_ID`

- **Relation analyzed:** `R_A3` (21 attributes), dependencies FD6, FD7, FD10, FD11, key
  `T_ID`, normal form 2NF.
- **3NF violations:** `M_ID → M_*, C_ID` and `O_ID → O_*, U_ID, M_ID`. **Split first on
  `M_ID`**, because `Orders` still needs `M_ID`.
- **Decomposition dependency:** `M_ID → M_*, C_ID` (FD6).
- **New relation `R_MARKETS`** = `{ M_ID, M_*, C_ID }` (5 attributes). Dependencies: FD6, FD7.
  Candidate keys: `M_ID`, `{C_ID, M_QUOTE_CURRENCY}`. Primary key: `M_ID`. Normal form: BCNF.
- **Residual relation `R_A4`** = `R_A3 − { M_*, C_ID }` (17 attributes). No dependency left
  needs `C_ID`. Dependencies: FD10, FD11. Candidate key and primary key: `T_ID`. Normal form: 2NF.
- **Dependency preservation:** FD6 and FD7 are in `R_MARKETS`, and FD10 and FD11 are in
  `R_A4`. ✓
- **Lossless join:** `R_MARKETS ∩ R_A4 = { M_ID }`, and `M_ID → R_MARKETS` (FD6). ✓

### Step 3NF-5 — transitive dependency through `O_ID`

- **Relation analyzed:** `R_A4` = `{ T_ID, T_*, O_ID, O_*, U_ID, M_ID }` (17 attributes),
  dependencies FD10, FD11, candidate key and primary key `T_ID`, normal form 2NF.
- **3NF violations:** only `O_ID → O_*, U_ID, M_ID`. **Split on `O_ID`**.
- **Decomposition dependency:** `O_ID → O_*, U_ID, M_ID` (FD10).
- **New relation `R_ORDERS`** = `{ O_ID, O_*, U_ID, M_ID }` (11 attributes). Dependencies:
  FD10. Candidate key: `O_ID`. Normal form: BCNF.
- **Residual relation `R_TRANSACTIONS`** = `R_A4 − { O_*, U_ID, M_ID }` = `{ T_ID, T_*, O_ID }`
  (7 attributes). Dependencies: FD11. Candidate key: `T_ID`. Normal form: BCNF. Keeping `U_ID`
  here would have left the transitive dependency `T_ID → O_ID → U_ID` inside the relation.
  `T_ID → U_ID` was removed from the cover as redundant, so nothing is lost.
- **Dependency preservation:** FD10 is in `R_ORDERS`, and FD11 is in `R_TRANSACTIONS`. ✓
- **Lossless join:** `R_ORDERS ∩ R_TRANSACTIONS = { O_ID }`, and `O_ID → R_ORDERS`
  (FD10). ✓

**Result of 3NF:** `R_USERS`, `R_CRYPTO`, `R_HOLDINGS`, `R_MARKETS`, `R_ORDERS`,
`R_TRANSACTIONS` (from `R_A`), and `R_B`, `R_C`, `R_D`, `R_E`, `R_F`, `S6` unchanged. 12
relations, all in 3NF, and all except `S6` in BCNF. All 18 dependencies are preserved.

## BCNF if possible

BCNF requires **every** determinant of a non-trivial dependency to be a superkey, even when
the dependent attribute is prime.

| Relation | Dependencies in force | Determinants | All superkeys? |
|---|---|---|---|
| `R_USERS` | FD1, FD2, FD3 | `U_ID`, `U_USERNAME`, `U_EMAIL` | yes |
| `R_CRYPTO` | FD4, FD5 | `C_ID`, `C_SYMBOL` | yes |
| `R_MARKETS` | FD6, FD7 | `M_ID`, `{C_ID, M_QUOTE_CURRENCY}` | yes |
| `R_HOLDINGS` | FD8, FD9 | `H_ID`, `{U_ID, C_ID}` | yes |
| `R_ORDERS` | FD10 | `O_ID` | yes |
| `R_TRANSACTIONS` | FD11 | `T_ID` | yes |
| `R_B` | FD13 | `OE_ID` | yes |
| `R_C` | FD12 | `MT_ID` | yes |
| `R_D` | FD14, FD15 | `MC_ID`, `{M_ID, MC_TIMEFRAME, MC_CANDLE_TIME}` | yes |
| `R_E` | FD16 | `W_ID` | yes |
| `R_F` | FD17, FD18 | `WI_ID`, `{W_ID, C_ID}` | yes |
| `S6` | `MC_ID → MC_TIMEFRAME, MC_CANDLE_TIME`; `WI_ID → W_ID`; derived ones such as `MT_ID, MC_TIMEFRAME, MC_CANDLE_TIME → MC_ID` and `MT_ID, W_ID → WI_ID` | `MC_ID`, `WI_ID`, `{MT_ID, MC_TIMEFRAME, MC_CANDLE_TIME}`, `{MT_ID, W_ID}`, … | **no** |

**Dependencies that violate BCNF — only in `S6`.** `MC_ID` determines `MC_TIMEFRAME` and
`MC_CANDLE_TIME`, and `WI_ID` determines `W_ID`, but neither `MC_ID` nor `WI_ID` is a superkey
of `S6`. 3NF allowed this because the dependent attributes are prime. BCNF does not. The derived
dependencies all involve `W_ID` or `MC_TIMEFRAME`/`MC_CANDLE_TIME`, so they disappear once the
two steps below remove those attributes.

### Step BCNF-1 — `MC_ID → MC_TIMEFRAME, MC_CANDLE_TIME`

- **Relation analyzed:** `S6` (8 attributes), dependencies as in the table above, candidate
  keys K1–K4, primary key K1, normal form 3NF.
- **BCNF violations:** `MC_ID → MC_TIMEFRAME, MC_CANDLE_TIME` and `WI_ID → W_ID`, and the
  derived ones that depend on them. **Split first on `MC_ID`**. The order does not matter
  here, because the two violations share no attribute.
- **Decomposition dependency:** `MC_ID → MC_TIMEFRAME, MC_CANDLE_TIME`. `MC_ID` is not a
  superkey of `S6`.
- **New relation** `{ MC_ID, MC_TIMEFRAME, MC_CANDLE_TIME }`. Dependencies:
  `MC_ID → MC_TIMEFRAME, MC_CANDLE_TIME`. Key: `MC_ID`. Normal form: BCNF. It is a
  projection of `R_D`, which already contains these attributes with the same key, so it adds no
  information and is merged into `R_D`.
- **Residual relation `S7`** = `{ T_ID, OE_ID, MT_ID, MC_ID, W_ID, WI_ID }` (6 attributes).
  Dependencies: `WI_ID → W_ID`, and derived ones such as `MT_ID, W_ID → WI_ID`. Candidate
  keys: `{T_ID, OE_ID, MT_ID, MC_ID, WI_ID}` (K1) and `{T_ID, OE_ID, MT_ID, MC_ID, W_ID}` (K2).
  Normal form: 3NF.
- **Dependency preservation:** no dependency of the cover is affected. FD14 and FD15 are in
  `R_D`. ✓
- **Lossless join:** the intersection is `{ MC_ID }`, and `MC_ID → { MC_ID, MC_TIMEFRAME,
  MC_CANDLE_TIME }`. ✓

### Step BCNF-2 — `WI_ID → W_ID`

- **Relation analyzed:** `S7` (6 attributes), dependencies `WI_ID → W_ID` and derived ones,
  candidate keys K1, K2, primary key K1, normal form 3NF.
- **BCNF violations:** only `WI_ID → W_ID` (and the derived `MT_ID, W_ID → WI_ID`). **Split on
  `WI_ID`**.
- **Decomposition dependency:** `WI_ID → W_ID`. `WI_ID` is not a superkey of `S7`.
- **New relation** `{ WI_ID, W_ID }`. Dependencies: `WI_ID → W_ID`. Key: `WI_ID`. Normal
  form: BCNF. For the same reason as in BCNF-1, it is merged into `R_F`.
- **Residual relation `R_KEY`** = `{ T_ID, OE_ID, MT_ID, MC_ID, WI_ID }` (5 attributes). No
  non-trivial dependency holds among these attributes. Candidate key: all five (= K1).
  Normal form: BCNF.
- **Dependency preservation:** no dependency of the cover is affected. FD17 and FD18 are in
  `R_F`. The derived dependencies of `S6`/`S7` follow from FD12, FD15, FD17 and FD18, which
  are all preserved. ✓
- **Lossless join:** the intersection is `{ WI_ID }`, and `WI_ID → { WI_ID, W_ID }`. ✓

**Result: every relation is in BCNF.** The decomposition into these 12 relations is lossless
(each of the 13 binary steps passed the test) and preserves all 18 dependencies of the
canonical cover.

## Final result and discussion

### Normalized relational model

Each relation is followed by its keys (primary key first). An attribute that is the
identifier of another relation is marked `→` with that relation.

```
R_USERS          (U_ID, U_USERNAME, U_EMAIL, U_FULL_NAME, U_PASSWORD_HASH,
                  U_AVAILABLE_BALANCE, U_INVESTED_BALANCE, U_RESERVED_BALANCE,
                  U_CREATED_AT, U_UPDATED_AT)
                  keys: U_ID; U_USERNAME; U_EMAIL
R_CRYPTO         (C_ID, C_SYMBOL, C_NAME, C_CREATED_AT)
                  keys: C_ID; C_SYMBOL
R_MARKETS        (M_ID, C_ID → R_CRYPTO, M_QUOTE_CURRENCY, M_IS_ACTIVE, M_CREATED_AT)
                  keys: M_ID; {C_ID, M_QUOTE_CURRENCY}
R_HOLDINGS       (H_ID, U_ID → R_USERS, C_ID → R_CRYPTO, H_QUANTITY,
                  H_RESERVED_QUANTITY, H_AVG_PRICE, H_CREATED_AT, H_UPDATED_AT)
                  keys: H_ID; {U_ID, C_ID}
R_ORDERS         (O_ID, U_ID → R_USERS, M_ID → R_MARKETS, O_SIDE, O_TYPE, O_STATUS,
                  O_QUANTITY, O_FILLED_QUANTITY, O_PRICE, O_PLACED_AT, O_EXECUTED_AT)
                  key: O_ID
R_TRANSACTIONS   (T_ID, O_ID → R_ORDERS, T_TYPE, T_AMOUNT, T_CURRENCY, T_CREATED_AT,
                  T_DESCRIPTION)
                  key: T_ID
R_MARKET_TRADES  (MT_ID, M_ID → R_MARKETS, MT_EXECUTED_AT, MT_PRICE, MT_QUANTITY,
                  MT_SIDE, MT_SOURCE, O_ID_FILLSBUY → R_ORDERS (nullable),
                  O_ID_FILLSSELL → R_ORDERS (nullable))              [= R_C]
                  key: MT_ID
R_ORDER_EVENTS   (OE_ID, O_ID → R_ORDERS, OE_EVENT_TYPE, OE_QUANTITY, OE_PRICE,
                  OE_STATUS_AFTER, OE_CREATED_AT)                     [= R_B]
                  key: OE_ID
R_MARKET_CANDLES (MC_ID, M_ID → R_MARKETS, MC_TIMEFRAME, MC_OPEN, MC_HIGH, MC_LOW,
                  MC_CLOSE, MC_VOLUME, MC_CANDLE_TIME)                [= R_D]
                  keys: MC_ID; {M_ID, MC_TIMEFRAME, MC_CANDLE_TIME}
R_WATCHLISTS     (W_ID, U_ID → R_USERS, W_NAME, W_CREATED_AT)         [= R_E]
                  key: W_ID
R_WATCHLIST_ITEMS(WI_ID, W_ID → R_WATCHLISTS, C_ID → R_CRYPTO, WI_ADDED_AT)  [= R_F]
                  keys: WI_ID; {W_ID, C_ID}
R_KEY            (T_ID, OE_ID, MT_ID, MC_ID, WI_ID)                   [= R_KEY]
                  key: all five
```

### Discussion

**The eleven data relations are the P2 design, with one difference** (`transactions.user_id`,
explained below). Each relation is one entity set of the ER model:

| P5 relation | P2 table | How the relationships appear |
|---|---|---|
| `R_USERS` | `users` | — |
| `R_CRYPTO` | `crypto` | — |
| `R_MARKETS` | `markets` | `C_ID` = `crypto_id` (`QuotedOn`) |
| `R_HOLDINGS` | `holdings` | `U_ID` = `user_id` (`Holds`), `C_ID` = `crypto_id` (`PositionIn`) |
| `R_ORDERS` | `orders` | `U_ID` = `user_id` (`Places`), `M_ID` = `market_id` (`PlacedOn`) |
| `R_TRANSACTIONS` | `transactions` | `O_ID` = `related_order` (`Settles`); P2 also stores `user_id` (`Records`), see below |
| `R_MARKET_TRADES` | `market_trades` | `M_ID` = `market_id` (`Fills`), `O_ID_FILLSBUY` = `buy_order_id`, `O_ID_FILLSSELL` = `sell_order_id` |
| `R_ORDER_EVENTS` | `order_events` | `O_ID` = `order_id` (`Logs`) |
| `R_MARKET_CANDLES` | `market_candles` | `M_ID` = `market_id` (`Aggregates`) |
| `R_WATCHLISTS` | `watchlists` | `U_ID` = `user_id` (`Owns`) |
| `R_WATCHLIST_ITEMS` | `watchlist_items` | `W_ID` = `watchlist_id` (`Contains`), `C_ID` = `crypto_id` (`Lists`) |

The two methods produce the foreign keys differently. In P2 they come from a transformation
rule: a 1:N relationship becomes a column on the N side. Here, each one appears because a
dependency of kind (R), for example `O_ID → U_ID`, keeps the other entity's identifier in the
same relation as the entity that depends on it. The candidate keys also match, including the
composite ones (`{C_ID, M_QUOTE_CURRENCY}`, `{U_ID, C_ID}`, `{M_ID, MC_TIMEFRAME,
MC_CANDLE_TIME}`, `{W_ID, C_ID}`). They are exactly the `UNIQUE` constraints in
[`schema_creation.sql`](../../server/db/schema_creation.sql).

**The one difference: `transactions.user_id`.** The decomposition drops `U_ID` from
`R_TRANSACTIONS`, because `T_ID → U_ID` follows from `T_ID → O_ID` and `O_ID → U_ID`. That is
correct for every ledger entry that settles an order. It does not work for a **deposit**.
`Settles` is partial, so a deposit has no order, and without `user_id` a deposit would have no
owner at all. The de-normalized relation cannot show this case. Every one of its tuples
contains an order (every key contains `OE_ID`, and every order event has an order), so a
ledger entry without an order cannot appear in it. P2 therefore keeps `user_id` (the
relationship `Records`) as a deliberate exception. As a result, the implemented
`transactions` table is in **2NF but not in 3NF** (`related_order → user_id` is a transitive
dependency), and this is by design. For entries with an order,
`transactions.user_id` repeats the order's user. The only code that sets `related_order` (the buy
and sell inserts in `advanced_db.sql`) writes the user and the id of the same order row. No
database constraint enforces this.

**Two order columns in `market_trades`.** `FillsBuy` and `FillsSell` needed two role
attributes already in the de-normalized relation, and both end up in `R_MARKET_TRADES`.
They correspond to `buy_order_id` and `sell_order_id`.

**`R_KEY` belongs to the formal result, but it is not implemented as a table.** It is the
relation that contains a key of `R_EDUBERZA`, and the lossless-join result above holds for all
12 relations *including* it. It records no fact of the domain. It only says which ledger
entry, order event, trade, candle and watchlist item were put into the same tuple, and that
combination exists only because we started from one single relation. Not implementing it is
an implementation decision. The eleven implemented tables are not claimed to reconstruct
`R_EDUBERZA` on their own. They keep every attribute and every dependency of the canonical
cover, and that is what the application needs.

**`holdings.avg_price`** is shown as a *derived* attribute in the ER model: it can be
recomputed from the buy history. It is still stored, and that is a deliberate
denormalisation (see [RelationalDesign](../P2-RelationalDesign/RelationalDesign.md#normalisation)).
Normalisation cannot detect this. `H_ID → H_AVG_PRICE` is an ordinary functional dependency,
because "derivable from rows of another entity" is a property of the application logic
that maintains the value (see [UseCase0004](../P3-UseCaseModel/UseCase0004.md),
`ON CONFLICT … DO UPDATE`), not a dependency between attributes of one tuple.

**Which design is used going forward:** P2's, unchanged. The eleven data relations coincide
with the eleven tables of [`schema_creation.sql`](../../server/db/schema_creation.sql) and
[`advanced_db.sql`](../../server/db/advanced_db.sql) column for column, except for the
deliberately kept `transactions.user_id` explained above. So there are no database objects
to restructure, and the prototype and the reports of P6/P7 keep working against the same
schema.
