# Build Instructions

How to compile, configure, run and test the EduBerza prototype.
Linked from [PrototypeImplementation](PrototypeImplementation.md).

## Development environment description

| Tool        | Version tested        | Needed for                                                    |
|-------------|-----------------------|---------------------------------------------------------------|
| Go          | 1.26 (1.25+ works)    | Building `server/` (the CLI) and `bots/` (the market bot).     |
| PostgreSQL  | 16                    | The database. Docker image or the faculty server.              |
| Docker      | any recent            | Optional — brings up a local PostgreSQL in one command.        |
| `psql`      | any                   | Optional — running the SQL scripts by hand.                    |
| Java        | 21 (8+ works)         | Optional — only to open/edit the ER diagram in TerraER.         |
| DBeaver     | any recent            | Optional — only to export `relational_schema.jpg`.              |

Nothing else has to be installed. The only third-party Go dependency
(`github.com/lib/pq`, the PostgreSQL driver) is fetched automatically by
`go build` from `go.mod`/`go.sum`.

## Build instructions

All commands run from the repository root.

### 1. Configure the database connection

```sh
cp .env.example .env
```

The defaults in `.env.example` match the bundled Docker setup. To use the
faculty database instead, either edit `.env` or pass the values as real
environment variables — those take precedence over the file:

```sh
DBHOST=... DBPORT=5432 DBUSER=... DBPASSWORD=... DBNAME=... ./eduberza
```

`.env` is deliberately not committed (see `.gitignore`) because it holds a
password.

### 2. Start PostgreSQL

```sh
docker compose up -d
```

Skip this step if you are pointing at the faculty database.

### 3. Build

```sh
go build -o eduberza ./server
```

### 4. Create the schema and load the sample data

```sh
./eduberza -init
```

This runs `server/db/schema_creation.sql` and then `server/db/data_load.sql`.
Both are **compiled into the binary** (`go:embed`), so `-init` works regardless
of which directory you launch it from. It is destructive and idempotent — it
drops and recreates the whole `project` schema, so it is also the reset button
if a demo goes wrong. To reload only the data, keeping the schema:

```sh
./eduberza -load-data
```

The equivalent with `psql`, if you prefer to watch the statements run:

```sh
psql "postgresql://$DBUSER:$DBPASSWORD@$DBHOST:$DBPORT/$DBNAME" \
  -f server/db/schema_creation.sql
psql "postgresql://$DBUSER:$DBPASSWORD@$DBHOST:$DBPORT/$DBNAME" \
  -f server/db/data_load.sql
```

### 5. Run the prototype

```sh
./eduberza
```

Seed accounts — all with the password `test123`:

| Username  | Starting state                                        |
|-----------|-------------------------------------------------------|
| `alice`   | 8250.00 USD cash, holds 0.5 ETH — best demo account   |
| `bob`     | 5000.00 USD cash, no positions                        |
| `charlie` | 2500.00 USD cash, no positions                        |

### 6. Optional — run the market simulation bot

In a second terminal:

```sh
go run ./bots
```

The bot walks the price of every active market, inserts a row into
`market_trades` on each tick and upserts the current 1-minute candle. Prices in
the CLI change while it runs, because the current price is always read from the
most recent trade (`v_latest_prices`), never from a stored column.

## Testing instructions

### Mini-guide to the application

The CLI has two menus. Before logging in: **Register**, **Login**,
**Browse markets**. After logging in: **View balance**, **Deposit virtual
funds**, **Browse markets**, **Place market BUY order**, **Place market SELL
order**, **View portfolio**, **View transaction history**, **Manage watchlist**,
**Logout**.

You never have to remember an identifier. Markets are always printed as a
numbered list with their current price before you are asked which one you want,
and assets are referred to by symbol (`BTC`, `ETH`, …), never by database id.

### End-to-end smoke test

Verified on 2026-08-07 against PostgreSQL 16 with freshly loaded sample data.
Expected values are exact.

1. `./eduberza -init` — prints `Database initialised.`
2. `./eduberza`, then `[2] Login` → `alice` / `test123` → `Login successful.`
3. `[6] View portfolio` → one row: `ETH 0.5000` at avg 3500.000000, current
   3520.000000, value 1760.0000, unrealised P/L `+10.0000`. Cash available
   8250.0000, net worth 10010.0000.
4. `[4] Place market BUY order` → `BTC` → `0.01` →
   `Order executed: buy 0.0100 BTC @ 67140.000000 (notional 671.4000 USD)`.
5. `[6] View portfolio` → now BTC *and* ETH, total value 2431.4000, cash
   7578.6000 (= 8250.00 − 671.40), net worth still 10010.0000.
6. `[5] Place market SELL order` → `ETH` → `0.5` →
   `Order executed: sell 0.5000 ETH @ 3520.000000 (notional 1760.0000 USD)`.
7. `[7] View transaction history` → deposit, buy, buy, sell, newest first.
8. `[8] Manage watchlist` → `[1] List items` → alice's `Favorites` contains
   BTC, ETH, SOL with live prices.
9. `[9] Logout`, then `[0] Exit`.

### Testing the failure paths

These matter more than the happy path, because they are what proves the
transactions actually roll back:

- **Insufficient funds:** log in as `charlie` (2500 USD) and try to buy `1` BTC.
  Expect `Insufficient funds: need 67140.0000, have 2500.0000` and *no* change
  to any table — no order row, no ledger entry, no holding.
- **Insufficient holding:** as `bob` (no positions), try to sell `1` ETH.
  Expect `Insufficient holding: trying to sell 1.0000, hold 0.0000`.
- **Duplicate registration:** register with username `alice`. Expect
  `Username or email already taken.`
- **Wrong password:** log in as `alice` with any wrong password. Expect
  `Invalid credentials.` — and note the same message for an unknown username, so
  the prototype does not leak which accounts exist.

### For the public presentation

Demo with `alice` (already has a position, so the portfolio screen is not
empty), and register a brand-new account live to show UC0001. Run the bot in a
background terminal so the prices visibly move between two portfolio refreshes.

## Editing the ER diagram

TerraER is a third-party tool and is deliberately **not** committed to this
repository. Download the teacher's build from
<https://bazi.finki.ukim.mk/resources/Software/> and run it:

```sh
java -jar TerraER3.11.jar     # then File → Open → docs/ERModel_v01.xml
```

Save new versions as `ERModel_v02.xml`, `ERModel_v03.xml`, … and export a
matching PNG for each. TerraER does not add the extension itself — type
`.xml` explicitly or the file will not reopen.

## Up-to-date source code

The repository is pushed to the FINKI DEVELOP git server; see the Repositories
section in EPRMS for the clone URL and credentials.

### About the source code

- All source needed to run the prototype is in this repository: the CLI
  (`server/`), the market bot (`bots/`), the DDL script and the sample-data
  script (`server/db/`).
- Third-party Go libraries are **not** vendored — `go build` downloads
  `github.com/lib/pq` using the pinned versions in `go.mod` and `go.sum`.
- Third-party executables are **not** committed. `.gitignore` excludes `*.jar`;
  TerraER is downloaded from the URL above.
- No third-party images, styles or frameworks are used, and there are no
  images in the prototype at all — the interface is text.
