# Normalization

This phase deliberately ignores the design from [ERModel](../P1-ConceptualModel/ERModel.md)
(P1) and [RelationalDesign](../P2-RelationalDesign/RelationalDesign.md) (P2) as a starting
point. Instead it starts over from a single flat relation containing every attribute of the
model, derives the functional dependencies that hold on it, and decomposes it formally,
step by step, using only Armstrong's axioms and the standard normal-form definitions. The
[final section](#final-result-and-discussion) compares what falls out of that process with
the P2 design.

## De-normalized database form

### Building one relation out of the whole model

The ER model has ten entity/relationship sets carrying attributes (see
[ERModel](../P1-ConceptualModel/ERModel.md)): `Users`, `Cryptos`, `Markets`, `Orders`,
`Transactions`, `MarketTrades`, `MarketCandles`, `Watchlists`, and the two attributed
relationships `Holds` and `Contains`. Eight more relationships (`QuotedOn`, `PlacedOn`,
`Places`, `Records`, `Settles`, `Fills`, `Aggregates`, `Owns`) carry no attributes of their
own — in Chen notation they need none, because the diagram expresses the link itself as a
relationship, not a column. A single flat relation has no such device: the only way to keep
one entity's rows pointed at another's is a plain attribute holding the referenced key,
which is exactly what P2's ER-to-relational transformation already introduces for each of
those eight relationships (`markets.crypto_id`, `orders.market_id`, `orders.user_id`,
`transactions.user_id`, `transactions.related_order`, `market_trades.market_id`,
`market_candles.market_id`, `watchlists.user_id`). Those linking attributes are included
below for that reason — not because they were copied from P2's design, but because a "single
table with everything in it" cannot represent the model at all without them.

Every attribute name is prefixed by a two-or-three-letter code for the entity/relationship it
came from, because several names repeat across the model (`id`, `created_at`, `quantity`,
`type`, `name`, `price`, `side` all appear more than once) and the de-normalized relation may
not contain duplicate names.

| Prefix | Origin (P1 entity / relationship) | Attributes |
|---|---|---|
| `U_`  | Users        | `U_ID, U_USERNAME, U_EMAIL, U_FULL_NAME, U_PASSWORD_HASH, U_AVAILABLE_BALANCE, U_INVESTED_BALANCE, U_CREATED_AT, U_UPDATED_AT` |
| `C_`  | Cryptos      | `C_ID, C_SYMBOL, C_NAME, C_CREATED_AT` |
| `M_`  | Markets (+ `QuotedOn`) | `M_ID, M_CRYPTO_ID, M_QUOTE_CURRENCY, M_IS_ACTIVE, M_CREATED_AT` |
| `H_`  | `Holds` (+ surrogate key) | `H_ID, H_USER_ID, H_CRYPTO_ID, H_QUANTITY, H_RESERVED_QUANTITY, H_AVG_PRICE, H_CREATED_AT, H_UPDATED_AT` |
| `O_`  | Orders (+ `PlacedOn`, `Places`) | `O_ID, O_USER_ID, O_MARKET_ID, O_SIDE, O_TYPE, O_STATUS, O_QUANTITY, O_PRICE, O_PLACED_AT, O_EXECUTED_AT` |
| `T_`  | Transactions (+ `Records`, `Settles`) | `T_ID, T_USER_ID, T_TYPE, T_AMOUNT, T_CURRENCY, T_RELATED_ORDER, T_CREATED_AT, T_DESCRIPTION` |
| `MT_` | MarketTrades (+ `Fills`) | `MT_ID, MT_MARKET_ID, MT_EXECUTED_AT, MT_PRICE, MT_QUANTITY, MT_SIDE, MT_SOURCE` |
| `MC_` | MarketCandles (+ `Aggregates`) | `MC_ID, MC_MARKET_ID, MC_TIMEFRAME, MC_OPEN, MC_HIGH, MC_LOW, MC_CLOSE, MC_VOLUME, MC_CANDLE_TIME` |
| `W_`  | Watchlists (+ `Owns`) | `W_ID, W_USER_ID, W_NAME, W_CREATED_AT` |
| `WI_` | `Contains` (+ surrogate key) | `WI_ID, WI_WATCHLIST_ID, WI_CRYPTO_ID, WI_ADDED_AT` |

`H_ID` and `WI_ID` exist for the same reason they exist in P2: `Holds` and `Contains` are M:N
relationships with their own attributes, and giving each its own surrogate key (rather than
relying solely on the `{user,crypto}` / `{watchlist,crypto}` pair) is the same design choice
already justified in [RelationalDesign](../P2-RelationalDesign/RelationalDesign.md#descriptive-representation-of-the-relational-schema).

This gives **one relation, `R_EDUBERZA`, of 68 attributes:**

```
R_EDUBERZA(
  U_ID, U_USERNAME, U_EMAIL, U_FULL_NAME, U_PASSWORD_HASH, U_AVAILABLE_BALANCE,
  U_INVESTED_BALANCE, U_CREATED_AT, U_UPDATED_AT,
  C_ID, C_SYMBOL, C_NAME, C_CREATED_AT,
  M_ID, M_CRYPTO_ID, M_QUOTE_CURRENCY, M_IS_ACTIVE, M_CREATED_AT,
  H_ID, H_USER_ID, H_CRYPTO_ID, H_QUANTITY, H_RESERVED_QUANTITY, H_AVG_PRICE,
  H_CREATED_AT, H_UPDATED_AT,
  O_ID, O_USER_ID, O_MARKET_ID, O_SIDE, O_TYPE, O_STATUS, O_QUANTITY, O_PRICE,
  O_PLACED_AT, O_EXECUTED_AT,
  T_ID, T_USER_ID, T_TYPE, T_AMOUNT, T_CURRENCY, T_RELATED_ORDER, T_CREATED_AT,
  T_DESCRIPTION,
  MT_ID, MT_MARKET_ID, MT_EXECUTED_AT, MT_PRICE, MT_QUANTITY, MT_SIDE, MT_SOURCE,
  MC_ID, MC_MARKET_ID, MC_TIMEFRAME, MC_OPEN, MC_HIGH, MC_LOW, MC_CLOSE, MC_VOLUME,
  MC_CANDLE_TIME,
  W_ID, W_USER_ID, W_NAME, W_CREATED_AT,
  WI_ID, WI_WATCHLIST_ID, WI_CRYPTO_ID, WI_ADDED_AT
)
```

Every attribute is single-valued and atomic (a balance, a timestamp, a symbol, an amount —
nothing here is a list or a nested record), so `R_EDUBERZA` satisfies 1NF as soon as it is
written down. Whether it satisfies anything beyond that is exactly what the rest of this page
checks.

## Functional dependencies

### Canonical cover

Read directly off the model: each entity's/relationship's own key determines its own
attributes, nothing more. This is already minimal — no functional dependency below has an
extraneous attribute on its left side, and no dependent attribute is repeated on the right
side of more than one dependency, which is what "canonical cover" requires.

| # | Functional dependency | Source |
|---|---|---|
| FD1 | `U_ID → U_USERNAME, U_EMAIL, U_FULL_NAME, U_PASSWORD_HASH, U_AVAILABLE_BALANCE, U_INVESTED_BALANCE, U_CREATED_AT, U_UPDATED_AT` | Users |
| FD2 | `U_USERNAME → U_ID` | Users (`UNIQUE(username)`) |
| FD3 | `U_EMAIL → U_ID` | Users (`UNIQUE(email)`) |
| FD4 | `C_ID → C_SYMBOL, C_NAME, C_CREATED_AT` | Cryptos |
| FD5 | `C_SYMBOL → C_ID` | Cryptos (`UNIQUE(symbol)`) |
| FD6 | `M_ID → M_CRYPTO_ID, M_QUOTE_CURRENCY, M_IS_ACTIVE, M_CREATED_AT` | Markets |
| FD7 | `M_CRYPTO_ID, M_QUOTE_CURRENCY → M_ID` | Markets (`UNIQUE(crypto_id, quote_currency)`) |
| FD8 | `H_ID → H_USER_ID, H_CRYPTO_ID, H_QUANTITY, H_RESERVED_QUANTITY, H_AVG_PRICE, H_CREATED_AT, H_UPDATED_AT` | Holds |
| FD9 | `H_USER_ID, H_CRYPTO_ID → H_ID` | Holds (`UNIQUE(user_id, crypto_id)`) |
| FD10 | `O_ID → O_USER_ID, O_MARKET_ID, O_SIDE, O_TYPE, O_STATUS, O_QUANTITY, O_PRICE, O_PLACED_AT, O_EXECUTED_AT` | Orders |
| FD11 | `T_ID → T_USER_ID, T_TYPE, T_AMOUNT, T_CURRENCY, T_RELATED_ORDER, T_CREATED_AT, T_DESCRIPTION` | Transactions |
| FD12 | `MT_ID → MT_MARKET_ID, MT_EXECUTED_AT, MT_PRICE, MT_QUANTITY, MT_SIDE, MT_SOURCE` | MarketTrades |
| FD13 | `MC_ID → MC_MARKET_ID, MC_TIMEFRAME, MC_OPEN, MC_HIGH, MC_LOW, MC_CLOSE, MC_VOLUME, MC_CANDLE_TIME` | MarketCandles |
| FD14 | `MC_MARKET_ID, MC_TIMEFRAME, MC_CANDLE_TIME → MC_ID` | MarketCandles (`UNIQUE(market_id, timeframe, candle_time)`) |
| FD15 | `W_ID → W_USER_ID, W_NAME, W_CREATED_AT` | Watchlists |
| FD16 | `WI_ID → WI_WATCHLIST_ID, WI_CRYPTO_ID, WI_ADDED_AT` | Contains |
| FD17 | `WI_WATCHLIST_ID, WI_CRYPTO_ID → WI_ID` | Contains (`UNIQUE(watchlist_id, crypto_id)`) |

**Minimality, checked by example (Markets):** could FD7 drop an attribute from its left side?
`M_CRYPTO_ID` alone does not determine `M_ID` — many markets can reference the same crypto in
different quote currencies (that is the entire point of the market entity), so two rows can
share `M_CRYPTO_ID` and disagree on `M_ID`. `M_QUOTE_CURRENCY` alone fails the same way in the
other direction. Neither attribute is extraneous, so the left side of FD7 cannot shrink. The
same check applies to FD9, FD14 and FD17, whose composite left sides come directly from the
`UNIQUE` constraints already justified per-relation in
[RelationalDesign](../P2-RelationalDesign/RelationalDesign.md); none of those constraints
holds on a proper subset of its columns either.

**No redundant dependency:** each of FD1–FD17 has a right side that is not implied by any
other dependency in the set — for instance, nothing outside FD1 mentions `U_AVAILABLE_BALANCE`,
so FD1 cannot be derived from the rest and cannot be dropped. This set is the canonical cover.

### Dependencies carried by foreign keys

Six attributes above are foreign keys: `M_CRYPTO_ID`, `H_USER_ID`, `H_CRYPTO_ID`,
`O_USER_ID`, `O_MARKET_ID`, `T_USER_ID`, `T_RELATED_ORDER`, `MT_MARKET_ID`, `MC_MARKET_ID`,
`W_USER_ID`, `WI_WATCHLIST_ID`, `WI_CRYPTO_ID` — each one draws its values from the same
domain as some other attribute's key. Because of that, every dependency that holds on the
referenced key also holds, by substitution, on the referencing attribute:

| Foreign key | References | Therefore also determines |
|---|---|---|
| `M_CRYPTO_ID` | `C_ID` | `C_SYMBOL, C_NAME, C_CREATED_AT` |
| `H_USER_ID` | `U_ID` | all of `U_*` |
| `H_CRYPTO_ID` | `C_ID` | all of `C_*` |
| `O_USER_ID` | `U_ID` | all of `U_*` |
| `O_MARKET_ID` | `M_ID` | all of `M_*`, and transitively all of `C_*` |
| `T_USER_ID` | `U_ID` | all of `U_*` |
| `T_RELATED_ORDER` | `O_ID` | all of `O_*`, and transitively `U_*`, `M_*`, `C_*` (when not null) |
| `MT_MARKET_ID` | `M_ID` | all of `M_*`, transitively `C_*` |
| `MC_MARKET_ID` | `M_ID` | all of `M_*`, transitively `C_*` |
| `W_USER_ID` | `U_ID` | all of `U_*` |
| `WI_WATCHLIST_ID` | `W_ID` | all of `W_*`, transitively `U_*` |
| `WI_CRYPTO_ID` | `C_ID` | all of `C_*` |

None of these is added to the canonical cover — each is *derivable* from FD1–FD17 by
transitivity plus the foreign-key identity, which is exactly why a canonical cover excludes
them. They matter anyway: they are precisely the transitive dependencies the 3NF check below
has to rule out.

## Candidate keys and primary key

`Orders`, `Transactions`, `MarketTrades`, `MarketCandles`, `Holds`, `Watchlists` and
`Contains` are, with respect to each other, independent record types: nothing about an
order's id says anything about which market-candle row, or which unrelated transaction, or
which watchlist item is in the same tuple of `R_EDUBERZA` — a user can exist with zero of any
of them, and having one order says nothing about how many holdings, trades or candles exist
alongside it. (The one FK that crosses between two of these — `T_RELATED_ORDER` — is
nullable, so it cannot be relied on to always connect a transaction row back to an order.)
That means no proper subset of attributes can functionally determine all 68 attributes of
`R_EDUBERZA`: the only way to pin down a `H_*` value, an `O_*` value, a `T_*` value, an
`MT_*` value, an `MC_*` value, a `W_*` value *and* a `WI_*` value at once is to state one
identifying attribute from each cluster explicitly.

**Chosen primary key** (closure shown below):

```
{ U_ID, C_ID, M_ID, H_ID, O_ID, T_ID, MT_ID, MC_ID, W_ID, WI_ID }
```

**Closure check**, applying FD1–FD17 in turn to this set:

| Step | Attributes added | Dependency used |
|---|---|---|
| start | `U_ID, C_ID, M_ID, H_ID, O_ID, T_ID, MT_ID, MC_ID, W_ID, WI_ID` | — |
| 1 | `U_USERNAME, U_EMAIL, U_FULL_NAME, U_PASSWORD_HASH, U_AVAILABLE_BALANCE, U_INVESTED_BALANCE, U_CREATED_AT, U_UPDATED_AT` | FD1 (`U_ID → …`) |
| 2 | `C_SYMBOL, C_NAME, C_CREATED_AT` | FD4 |
| 3 | `M_CRYPTO_ID, M_QUOTE_CURRENCY, M_IS_ACTIVE, M_CREATED_AT` | FD6 |
| 4 | `H_USER_ID, H_CRYPTO_ID, H_QUANTITY, H_RESERVED_QUANTITY, H_AVG_PRICE, H_CREATED_AT, H_UPDATED_AT` | FD8 |
| 5 | `O_USER_ID, O_MARKET_ID, O_SIDE, O_TYPE, O_STATUS, O_QUANTITY, O_PRICE, O_PLACED_AT, O_EXECUTED_AT` | FD10 |
| 6 | `T_USER_ID, T_TYPE, T_AMOUNT, T_CURRENCY, T_RELATED_ORDER, T_CREATED_AT, T_DESCRIPTION` | FD11 |
| 7 | `MT_MARKET_ID, MT_EXECUTED_AT, MT_PRICE, MT_QUANTITY, MT_SIDE, MT_SOURCE` | FD12 |
| 8 | `MC_MARKET_ID, MC_TIMEFRAME, MC_OPEN, MC_HIGH, MC_LOW, MC_CLOSE, MC_VOLUME, MC_CANDLE_TIME` | FD13 |
| 9 | `W_USER_ID, W_NAME, W_CREATED_AT` | FD15 |
| 10 | `WI_WATCHLIST_ID, WI_CRYPTO_ID, WI_ADDED_AT` | FD16 |

The closure now contains all 68 attributes, so the set is a superkey; removing any one of its
ten attributes drops an entire cluster that nothing else in the set can reach (e.g. drop
`T_ID` and no remaining attribute determines any `T_*` value), so it is minimal — a candidate
key.

**It is not the only one.** Any attribute that is itself a determinant of a whole cluster can
stand in for that cluster's id — `U_USERNAME` or `U_EMAIL` for `U_ID` (FD2/FD3), `C_SYMBOL`
for `C_ID` (FD5), `{M_CRYPTO_ID, M_QUOTE_CURRENCY}` for `M_ID` (FD7), `{H_USER_ID,
H_CRYPTO_ID}` for `H_ID` (FD9), `{MC_MARKET_ID, MC_TIMEFRAME, MC_CANDLE_TIME}` for `MC_ID`
(FD14), `{WI_WATCHLIST_ID, WI_CRYPTO_ID}` for `WI_ID` (FD17) — giving 3 × 2 × 2 × 2 × 1 × 1 ×
1 × 2 × 1 × 2 = 96 candidate keys in total. The all-surrogate-id combination above is chosen
as **primary key** for the same reason `id` was chosen over `username`/`email`/`symbol`/etc.
per entity in [ERModel](../P1-ConceptualModel/ERModel.md): it is opaque, and none of its parts
are things a user would ever legitimately change.

**Normal form of `R_EDUBERZA` before decomposition:** 1NF only, and barely that — see 2NF
below. It cannot be in 2NF, 3NF or BCNF, since each of those requires 2NF as a precondition.

## 1NF decomposition

No decomposition happens at this step. 1NF requires atomic, single-valued attributes and no
repeating groups; `R_EDUBERZA` was built that way from the start (every column above is a
single scalar), so the relation already satisfies 1NF as written in
[De-normalized database form](#de-normalized-database-form). The real work starts at 2NF.

## 2NF decomposition

**Relation analyzed:** `R_EDUBERZA`, all 68 attributes, primary key
`{U_ID, C_ID, M_ID, H_ID, O_ID, T_ID, MT_ID, MC_ID, W_ID, WI_ID}` (10 attributes), FD1–FD17
in force.

**Current normal form:** 1NF only (previous section).

**Violations:** 2NF forbids a non-prime attribute from depending on *part* of a candidate
key. Every single functional dependency in the canonical cover (FD1–FD17) has a left side
that is a **proper subset** of the ten-attribute primary key — `U_ID` alone, `C_ID` alone, …,
down to the two-attribute `{WI_WATCHLIST_ID, WI_CRYPTO_ID}`. There is no non-prime attribute
in `R_EDUBERZA` that depends on the whole ten-attribute key and nothing smaller. In other
words, *every* non-prime attribute violates 2NF at once — the violation is not a handful of
stray columns to peel off, it is the entire relation, because gluing ten independent record
types together under one artificial composite key was never going to satisfy 2NF to begin
with.

**Decomposition.** This uses 3NF/BCNF **synthesis** (Bernstein's algorithm) rather than the
binary decomposition algorithm: since the canonical cover is already in hand (as the phase
instructions recommend building first), synthesis creates one relation per left-hand side in
the cover directly, instead of hunting for one offending dependency at a time and splitting
in two repeatedly. Grouping FD1–FD17 by determinant produces ten relations:

| New relation | Attributes | Key(s) | Source FDs |
|---|---|---|---|
| `R_USERS` | `U_ID, U_USERNAME, U_EMAIL, U_FULL_NAME, U_PASSWORD_HASH, U_AVAILABLE_BALANCE, U_INVESTED_BALANCE, U_CREATED_AT, U_UPDATED_AT` | `U_ID`, `U_USERNAME`, `U_EMAIL` | FD1, FD2, FD3 |
| `R_CRYPTO` | `C_ID, C_SYMBOL, C_NAME, C_CREATED_AT` | `C_ID`, `C_SYMBOL` | FD4, FD5 |
| `R_MARKETS` | `M_ID, M_CRYPTO_ID, M_QUOTE_CURRENCY, M_IS_ACTIVE, M_CREATED_AT` | `M_ID`, `{M_CRYPTO_ID, M_QUOTE_CURRENCY}` | FD6, FD7 |
| `R_HOLDINGS` | `H_ID, H_USER_ID, H_CRYPTO_ID, H_QUANTITY, H_RESERVED_QUANTITY, H_AVG_PRICE, H_CREATED_AT, H_UPDATED_AT` | `H_ID`, `{H_USER_ID, H_CRYPTO_ID}` | FD8, FD9 |
| `R_ORDERS` | `O_ID, O_USER_ID, O_MARKET_ID, O_SIDE, O_TYPE, O_STATUS, O_QUANTITY, O_PRICE, O_PLACED_AT, O_EXECUTED_AT` | `O_ID` | FD10 |
| `R_TRANSACTIONS` | `T_ID, T_USER_ID, T_TYPE, T_AMOUNT, T_CURRENCY, T_RELATED_ORDER, T_CREATED_AT, T_DESCRIPTION` | `T_ID` | FD11 |
| `R_MARKET_TRADES` | `MT_ID, MT_MARKET_ID, MT_EXECUTED_AT, MT_PRICE, MT_QUANTITY, MT_SIDE, MT_SOURCE` | `MT_ID` | FD12 |
| `R_MARKET_CANDLES` | `MC_ID, MC_MARKET_ID, MC_TIMEFRAME, MC_OPEN, MC_HIGH, MC_LOW, MC_CLOSE, MC_VOLUME, MC_CANDLE_TIME` | `MC_ID`, `{MC_MARKET_ID, MC_TIMEFRAME, MC_CANDLE_TIME}` | FD13, FD14 |
| `R_WATCHLISTS` | `W_ID, W_USER_ID, W_NAME, W_CREATED_AT` | `W_ID` | FD15 |
| `R_WATCHLIST_ITEMS` | `WI_ID, WI_WATCHLIST_ID, WI_CRYPTO_ID, WI_ADDED_AT` | `WI_ID`, `{WI_WATCHLIST_ID, WI_CRYPTO_ID}` | FD16, FD17 |

Every one of these ten relations now has **all** of its non-prime attributes depending on its
**whole** key (in every case there is only one non-composite or one designated key doing the
determining, so 2NF holds trivially in each).

**Dependency preservation.** FD1–FD17 is the canonical cover of `R_EDUBERZA`. Each FD's
determinant and every one of its dependent attributes land inside exactly one of the ten new
relations (see the "Source FDs" column above — no FD is split across two relations). The
union of the FDs that hold on `R_USERS, …, R_WATCHLIST_ITEMS` is therefore exactly FD1–FD17
again: nothing was lost.

**Lossless join.** For every pair (referencing relation, referenced relation) connected by a
foreign key — `R_MARKETS.M_CRYPTO_ID → R_CRYPTO.C_ID`, `R_HOLDINGS.H_USER_ID → R_USERS.U_ID` /
`R_HOLDINGS.H_CRYPTO_ID → R_CRYPTO.C_ID`, `R_ORDERS.O_USER_ID → R_USERS.U_ID` /
`R_ORDERS.O_MARKET_ID → R_MARKETS.M_ID`, `R_TRANSACTIONS.T_USER_ID → R_USERS.U_ID` /
`R_TRANSACTIONS.T_RELATED_ORDER → R_ORDERS.O_ID`, `R_MARKET_TRADES.MT_MARKET_ID →
R_MARKETS.M_ID`, `R_MARKET_CANDLES.MC_MARKET_ID → R_MARKETS.M_ID`,
`R_WATCHLISTS.W_USER_ID → R_USERS.U_ID`, `R_WATCHLIST_ITEMS.WI_WATCHLIST_ID →
R_WATCHLISTS.W_ID` / `R_WATCHLIST_ITEMS.WI_CRYPTO_ID → R_CRYPTO.C_ID` — the join attribute on
the "one" side is that relation's own primary key (`U_ID`, `C_ID`, `M_ID`, `O_ID`, `W_ID`).
A join on a foreign key equated to the primary key it references is the textbook sufficient
condition for a lossless decomposition (`Ri ∩ Rj` is a key of `Rj`), so re-joining all ten
relations on their foreign-key/primary-key pairs reconstructs `R_EDUBERZA` exactly, with no
spurious rows and none missing.

## 3NF decomposition

**Relations analyzed:** each of the ten relations produced above, individually.

For each relation, 3NF asks whether any non-prime attribute is *transitively* dependent on a
key — i.e. determined by another non-prime attribute rather than directly by the key. This is
exactly where the foreign-key-carried dependencies from
[Dependencies carried by foreign keys](#dependencies-carried-by-foreign-keys) have to be
checked, because that table is precisely the list of "dependency that would cause a problem at
the next higher normal form" the phase template asks for.

**Worked example — `R_MARKETS`.** Its key `M_ID` determines `M_CRYPTO_ID`, and
`M_CRYPTO_ID → C_SYMBOL, C_NAME, C_CREATED_AT` also holds (`M_CRYPTO_ID` draws its values from
`C_ID`'s domain). If `C_SYMBOL`, `C_NAME` and `C_CREATED_AT` were still columns of
`R_MARKETS`, this would be exactly the transitive dependency `M_ID → M_CRYPTO_ID → C_SYMBOL`
that violates 3NF. They are not: the 2NF step above already put them in `R_CRYPTO`, keyed
directly by `C_ID` (FD4), because FD4 — not the derived `M_CRYPTO_ID → C_SYMBOL` — is what the
canonical cover actually contains. `R_MARKETS` itself has no attribute that determines another
non-prime attribute of `R_MARKETS`; the transitive dependency is real, but it points *out* of
the relation, not within it.

The same reasoning applies to every other foreign key in the list: `H_USER_ID`/`H_CRYPTO_ID`,
`O_USER_ID`/`O_MARKET_ID`, `T_USER_ID`/`T_RELATED_ORDER`, `MT_MARKET_ID`, `MC_MARKET_ID`,
`W_USER_ID`, `WI_WATCHLIST_ID`/`WI_CRYPTO_ID` are all foreign keys sitting *alongside* a
non-key attribute set that depends only on their own relation's key, never on the foreign key
itself. None of `R_USERS`, `R_CRYPTO`, `R_HOLDINGS`, `R_ORDERS`, `R_TRANSACTIONS`,
`R_MARKET_TRADES`, `R_MARKET_CANDLES`, `R_WATCHLISTS`, `R_WATCHLIST_ITEMS` has a non-prime
attribute that another non-prime attribute of the *same* relation determines.

**Conclusion:** synthesising directly from the canonical cover in the 2NF step already
avoided every transitive dependency — there is nothing left to decompose for 3NF. All ten
relations from the previous section satisfy 3NF unchanged.

## BCNF if possible

**Relations analyzed:** the same ten relations, checked against the stricter BCNF rule: every
determinant of every functional dependency that holds on the relation must be a candidate key
of that relation (3NF allows an exception when the dependent side is prime; BCNF does not).

| Relation | Functional dependencies in force | Determinant | Is it a candidate key? |
|---|---|---|---|
| `R_USERS` | FD1, FD2, FD3 | `U_ID`, `U_USERNAME`, `U_EMAIL` | Yes — all three are candidate keys |
| `R_CRYPTO` | FD4, FD5 | `C_ID`, `C_SYMBOL` | Yes — both candidate keys |
| `R_MARKETS` | FD6, FD7 | `M_ID`, `{M_CRYPTO_ID, M_QUOTE_CURRENCY}` | Yes — both candidate keys |
| `R_HOLDINGS` | FD8, FD9 | `H_ID`, `{H_USER_ID, H_CRYPTO_ID}` | Yes — both candidate keys |
| `R_ORDERS` | FD10 | `O_ID` | Yes — the only candidate key |
| `R_TRANSACTIONS` | FD11 | `T_ID` | Yes — the only candidate key |
| `R_MARKET_TRADES` | FD12 | `MT_ID` | Yes — the only candidate key |
| `R_MARKET_CANDLES` | FD13, FD14 | `MC_ID`, `{MC_MARKET_ID, MC_TIMEFRAME, MC_CANDLE_TIME}` | Yes — both candidate keys |
| `R_WATCHLISTS` | FD15 | `W_ID` | Yes — the only candidate key |
| `R_WATCHLIST_ITEMS` | FD16, FD17 | `WI_ID`, `{WI_WATCHLIST_ID, WI_CRYPTO_ID}` | Yes — both candidate keys |

Every determinant in every relation is one of that relation's own candidate keys. **All ten
relations are already in BCNF** — the highest of the four normal forms this phase asks for,
reached in the same step that fixed 2NF. This is not a coincidence: it happens because the
canonical cover already grouped each relation's own key directly against its own attributes
with no attribute appearing on the right side of two different relations' dependencies, which
is exactly what synthesis from a canonical cover guarantees when, as here, none of the
per-cluster functional dependencies overlap.

No further decomposition is possible or necessary; splitting any of the ten relations further
would only separate attributes that already depend on the *whole* key of a BCNF relation,
which cannot fix anything and only costs a join.

## Final result and discussion

### Normalized relational model

```
R_USERS          (U_ID, U_USERNAME, U_EMAIL, U_FULL_NAME, U_PASSWORD_HASH,
                   U_AVAILABLE_BALANCE, U_INVESTED_BALANCE, U_CREATED_AT, U_UPDATED_AT)
R_CRYPTO         (C_ID, C_SYMBOL, C_NAME, C_CREATED_AT)
R_MARKETS        (M_ID, M_CRYPTO_ID → R_CRYPTO, M_QUOTE_CURRENCY, M_IS_ACTIVE, M_CREATED_AT)
R_HOLDINGS       (H_ID, H_USER_ID → R_USERS, H_CRYPTO_ID → R_CRYPTO, H_QUANTITY,
                   H_RESERVED_QUANTITY, H_AVG_PRICE, H_CREATED_AT, H_UPDATED_AT)
R_ORDERS         (O_ID, O_USER_ID → R_USERS, O_MARKET_ID → R_MARKETS, O_SIDE, O_TYPE,
                   O_STATUS, O_QUANTITY, O_PRICE, O_PLACED_AT, O_EXECUTED_AT)
R_TRANSACTIONS   (T_ID, T_USER_ID → R_USERS, T_TYPE, T_AMOUNT, T_CURRENCY,
                   T_RELATED_ORDER → R_ORDERS, T_CREATED_AT, T_DESCRIPTION)
R_MARKET_TRADES  (MT_ID, MT_MARKET_ID → R_MARKETS, MT_EXECUTED_AT, MT_PRICE, MT_QUANTITY,
                   MT_SIDE, MT_SOURCE)
R_MARKET_CANDLES (MC_ID, MC_MARKET_ID → R_MARKETS, MC_TIMEFRAME, MC_OPEN, MC_HIGH, MC_LOW,
                   MC_CLOSE, MC_VOLUME, MC_CANDLE_TIME)
R_WATCHLISTS     (W_ID, W_USER_ID → R_USERS, W_NAME, W_CREATED_AT)
R_WATCHLIST_ITEMS(WI_ID, WI_WATCHLIST_ID → R_WATCHLISTS, WI_CRYPTO_ID → R_CRYPTO, WI_ADDED_AT)
```

Ten relations, every one in BCNF, connected by the eleven foreign keys spelled out above.

### Discussion

**This is the P2 design.** Strip the `U_`/`C_`/`M_`/… prefixes back to plain column names and
`R_USERS, R_CRYPTO, R_MARKETS, R_HOLDINGS, R_ORDERS, R_TRANSACTIONS, R_MARKET_TRADES,
R_MARKET_CANDLES, R_WATCHLISTS, R_WATCHLIST_ITEMS` are, attribute for attribute and key for
key, `users, crypto, markets, holdings, orders, transactions, market_trades, market_candles,
watchlists, watchlist_items` from
[RelationalDesign](../P2-RelationalDesign/RelationalDesign.md). Every foreign key matches,
every candidate key matches (including the less obvious composite ones — `{user_id,
crypto_id}` on `holdings`, `{crypto_id, quote_currency}` on `markets`, `{market_id, timeframe,
candle_time}` on `market_candles`), and the normal form matches (P2 already claimed 3NF; this
phase shows the stronger result that the design is actually in BCNF).

That is not a coincidence of two people happening to agree — it is what should happen when a
design is derived correctly twice by two different methods from the same underlying model:
P2 got here by applying the standard ER-to-relational transformation rules (each entity
becomes a table on its own key, each attributed M:N relationship becomes a table on the
combined key, each attributeless 1:N relationship becomes a foreign key on the "many" side).
This phase got here by ignoring that transformation entirely, writing down only the
attributes and the functional dependencies they obey, and mechanically applying 2NF/3NF/BCNF
synthesis. Landing on the same ten relations either means the P2 transformation rules are
sound for this particular model (which they are, for exactly the reason [RelationalDesign](../P2-RelationalDesign/RelationalDesign.md#normalisation)
already argued: single-column UUID primary keys everywhere rule out partial dependencies by
construction, and no non-key attribute references another non-key attribute anywhere in the
model, which rules out transitive dependencies too), or it is a coincidence spanning ten
independently-checked relations and dozens of functional dependencies — the first explanation
is the only credible one.

**The one substantive difference** is `holdings.avg_price`, which P2 documents as a
*derived* attribute — the running weighted-average buy price, recomputable from the `buy` rows
in `transactions` — kept as a stored column anyway for read performance
([RelationalDesign](../P2-RelationalDesign/RelationalDesign.md#normalisation) calls this out
explicitly as an accepted denormalisation). Nothing in this phase's functional-dependency
analysis can see that `H_AVG_PRICE` is derivable from `T_*` rows rather than stored
independently — FD8 (`H_ID → H_AVG_PRICE`) is a perfectly ordinary functional dependency
either way, because *derivability from a different relation's rows* is a property of the data
and the application logic that maintains it (see
[UseCase0004](../P3-UseCaseModel/UseCase0004.md)'s `ON CONFLICT … DO UPDATE`), not something
that shows up as a violation of any single-relation normal form. Formal normalization and "no
column is a cached computation of other columns" are related but different concerns; this
phase only checked the first one.

**Which design is used going forward:** P2's, unchanged. Since the two designs coincide
exactly, "restructuring the database objects" means confirming there is nothing to change
rather than writing new DDL. [`server/db/schema_creation.sql`](../../server/db/schema_creation.sql)
already matches `R_USERS`…`R_WATCHLIST_ITEMS` column-for-column (including
`holdings.reserved_quantity`, added between P2 and this phase — see
[RelationalDesignAIUsage](../P2-RelationalDesign/RelationalDesignAIUsage.md#session-3--2026-09-16)
— which is `H_RESERVED_QUANTITY` above, correctly grouped under `R_HOLDINGS`'s key alongside
`H_QUANTITY` and not treated as needing a relation of its own). P4's prototype
(`server/trade.go`, `server/portfolio.go`) keeps working against the same schema without
change. [RelationalDesign](../P2-RelationalDesign/RelationalDesign.md) has been updated with a
short note pointing here as the formal validation of its normal-form claim.
