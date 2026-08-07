# Use-case model

## List of Actors / Roles

- **Visitor** — Anyone browsing the platform without an account. Can only view public market information.
  - [UC0001](UseCase0001.md) — Register new account
  - [UC0002](UseCase0002.md) — Log in

- **Trader** — A logged-in user managing their virtual funds and positions.
  - [UC0003](UseCase0003.md) — Deposit virtual funds
  - [UC0004](UseCase0004.md) — Place market BUY order
  - [UC0005](UseCase0005.md) — Place market SELL order
  - [UC0006](UseCase0006.md) — View portfolio and transaction history
  - [UC0007](UseCase0007.md) — Manage watchlist

- **Market Simulator** — An external automated system (the bot in `bots/`) that inserts simulated trades and candles into the database so prices move in the simulation.

## Use-case model diagram (optional)

*(Optional per the rubric; include one later if time allows.)*

## Realization details on selection of the most important use cases

Solo project → **at least 3 use cases required** (rubric: "at least 3 per team-member"). **7 use cases documented** for a safety margin. All are implemented in the P4 prototype; see `server/` for the Go source and [PrototypeImplementation](../P4-Prototype/PrototypeImplementation.md) for documented runs.

| Use case                               | Importance | Why documented                                                                            |
|----------------------------------------|------------|-------------------------------------------------------------------------------------------|
| [UC0001 — Register](UseCase0001.md)    | High       | Without it nothing else works; demonstrates `INSERT` with uniqueness check.               |
| [UC0002 — Login](UseCase0002.md)       | High       | Authenticates every `Trader` action; demonstrates `SELECT` with parameter binding.        |
| [UC0003 — Deposit](UseCase0003.md)     | High       | Shows a multi-row transaction: `UPDATE users` + `INSERT INTO transactions`.               |
| [UC0004 — Buy](UseCase0004.md)         | Very high  | Core of the exchange: `INSERT orders`, `UPDATE users`, `UPSERT holdings`, ledger, trade.  |
| [UC0005 — Sell](UseCase0005.md)        | Very high  | Dual of Buy; demonstrates row-level `FOR UPDATE` locking and cost-basis bookkeeping.      |
| [UC0006 — Portfolio](UseCase0006.md)   | High       | Demonstrates joins over `holdings`, `markets`, `crypto`, and a view (`v_portfolio`).      |
| [UC0007 — Watchlist](UseCase0007.md)   | Medium     | Demonstrates N-M relation handling and `ON CONFLICT` upsert semantics.                    |
