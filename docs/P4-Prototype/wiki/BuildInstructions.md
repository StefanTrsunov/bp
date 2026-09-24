= Build Instructions =

This page explains how to compile, configure, run and test the !EduBerza prototype.
It is linked from [wiki:PrototypeImplementation].

== Development environment description ==

||= Tool =||= Version tested =||= Needed for =||
|| Go || 1.26.0 (`go.mod` asks for 1.25 or newer) || Building `server/` (the CLI) and `bots/` (the market bot). ||
|| PostgreSQL || 16.3 (Docker container) || The database. Either the local Docker container or the faculty server. ||
|| Docker + Docker Compose || any recent || Optional. Starts a local PostgreSQL with one command. ||
|| `psql` || 16 || Optional. Only for running the SQL scripts by hand. ||
|| Java || 21 (8+ works) || Optional. Only to open or edit the ER diagram in TerraER. ||
|| DBeaver || any recent || Optional. Only to export `relational_schema.jpg`. ||

About the PostgreSQL version: `docker-compose.yml` uses the image `postgres` without a version
tag. Docker therefore starts whatever version of the official image it has pulled. On the
machine where the prototype was tested, that was PostgreSQL 16.3. The only extension the schema
needs is `pgcrypto` (`CREATE EXTENSION IF NOT EXISTS pgcrypto`). It ships with PostgreSQL and is
included in the official image.

You do not need to install anything else. The only third-party Go library is the PostgreSQL
driver `github.com/lib/pq`. `go build` downloads it automatically, at the version pinned in
`go.mod` and `go.sum`.

== Build instructions ==

Run all commands from the repository root.

=== 1. Configure the database connection ===

{{{
cp .env.example .env
}}}

The defaults in `.env.example` (`localhost:5433`, user `bp_project`, database `bp_database`)
match the bundled Docker setup. To use the faculty database instead, edit `.env`, or pass the
values as real environment variables. Real environment variables take precedence over the file:

{{{
DBHOST=... DBPORT=5432 DBUSER=... DBPASSWORD=... DBNAME=... ./eduberza
}}}

`.env` is not committed on purpose (see `.gitignore`), because it holds a password.

=== 2. Start PostgreSQL ===

{{{
docker compose up -d
}}}

Skip this step if you use the faculty database.

=== 3. Build ===

{{{
go build -o eduberza ./server
}}}

=== 4. Create the schema and load the sample data ===

{{{
./eduberza -init
}}}

This runs `server/db/schema_creation.sql` and then `server/db/data_load.sql`. It logs
`Running schema_creation.sql ...`, `Running data_load.sql ...` and `Database initialised.`,
then prints:

{{{
Schema initialised. Re-run without -init to start the CLI.
}}}

Both scripts are '''compiled into the binary''' (`go:embed`), so `-init` works from any
directory. It is destructive and can be run again any number of times: it drops and recreates
the whole `project` schema, so it also resets everything if a demo goes wrong. To reload only
the data and keep the schema:

{{{
./eduberza -load-data          # prints "Sample data reloaded."
}}}

If you prefer to watch the statements run, the same can be done with `psql`:

{{{
psql "postgresql://$DBUSER:$DBPASSWORD@$DBHOST:$DBPORT/$DBNAME" \
  -f server/db/schema_creation.sql
psql "postgresql://$DBUSER:$DBPASSWORD@$DBHOST:$DBPORT/$DBNAME" \
  -f server/db/data_load.sql
}}}

=== 5. Run the prototype ===

{{{
./eduberza
}}}

=== 6. Optional: run the market simulation bot ===

In a second terminal, also from the repository root (the bot reads `.env` from the current
directory):

{{{
go run ./bots                  # add -interval 1s for faster ticks; the default is 3s
}}}

On every tick the bot moves the price of every active market by a small random step, inserts a
row into `market_trades` and updates the current 1-minute candle. Prices in the CLI change
while it runs, because the current price is always read from the most recent trade
(`v_latest_prices`) and never from a stored column. Leave the bot off if you want the exact
numbers in the tests below.

=== 7. Optional: richer data for the P6 reports ===

`data_load.sql` seeds only a few minutes of trade history. That is not enough for the
top traders and market performance reports of [wiki:AdvancedReports] (menu `[10]` and `[11]`)
to show more than one period. To see more interesting results, load five quarters of synthetic
history on top:

{{{
psql "postgresql://$DBUSER:$DBPASSWORD@$DBHOST:$DBPORT/$DBNAME" \
  -f server/db/reports_demo_data.sql
}}}

This script is not part of `-init` or `-load-data` on purpose. The header of
`reports_demo_data.sql`, shown below, explains why. Running it never changes the balances that
the tests below check.

{{{
-- reports_demo_data.sql
-- EduBerza - optional historical data for the P6 reports
-- Course: Databases 2025/2026 Winter, FINKI UKIM
--
-- data_load.sql only seeds ~10 minutes of trade history, which is enough to
-- demonstrate UC0001-UC0007 but not enough to show report_top_traders() or
-- report_market_performance() doing anything interesting: everything falls
-- into a single quarter, so "number of profitable periods" and "consistency"
-- are trivial and "market return" has almost no history to work with.
--
-- This script adds five quarters of synthetic transactions, market trades and
-- executed orders on top of an already-loaded data_load.sql, spanning
-- 2025-07 to 2026-07, so the two P6 reports have several periods and two
-- markets with opposite price trends to actually compare.
--
-- Deliberately NOT part of -init / -load-data: it only inserts into
-- transactions, market_trades and orders, and does not touch
-- users.available_balance/invested_balance or holdings, so it does not
-- disturb the balances the other use cases' documented "verified run"
-- sections depend on. Run it by hand, after data_load.sql, only to exercise
-- the two reports:
--
--   psql "$DATABASE_URL" -f server/db/schema_creation.sql
--   psql "$DATABASE_URL" -f server/db/data_load.sql
--   psql "$DATABASE_URL" -f server/db/reports_demo_data.sql
--
-- Idempotent: deletes its own previously-inserted rows (tagged via
-- description/source) before re-inserting.
}}}

== Testing instructions ==

=== How to launch and log in ===

Start the prototype with `./eduberza` after steps 1–4. The sample data creates three test
users. All of them have the password '''`test123`''':

||= Username =||= Starting state after `-init` =||
|| `alice` || 8250.00 USD available (1750.00 invested), holds 0.5 ETH bought at 3500.00. Watchlist "Favorites": BTC, ETH, SOL. Best demo account. ||
|| `bob` || 5000.00 USD available, no crypto. Watchlist "Bobs Picks": BTC, DOGE. ||
|| `charlie` || 2500.00 USD available, no crypto, no watchlist yet. ||

The five sample markets are ADA, BTC, DOGE, ETH and SOL, all quoted in USD. Their starting
last prices are 0.45375, 67140, 0.122, 3520 and 166.1.

=== Mini-guide to the application ===

You always answer with the number of a menu option. When you have to choose a market, a
holding or a crypto, the prototype prints a numbered list and you type the number from that
list. You never type an id or a symbol. A number that is not in the list is refused with
`Invalid choice, enter a number from 1 to N.`

'''Menu before login'''

||= Option =||= What it does and how to use it =||
|| `[1] Register` || Enter a username, an e-mail (must contain `@`), your full name and a password (at least 6 characters). You get `Account created. You can now log in.`, or `Invalid email.`, `Password must be at least 6 characters.` or `Username or email already taken.` A new account starts with 0 USD. ||
|| `[2] Login` || Enter your username and password. You get `Login successful.` and the second menu. A wrong password and an unknown username both give `Invalid credentials.` ||
|| `[3] Browse markets` || Prints the numbered list of markets with their last price. ||
|| `[0] Exit` || Ends the program. ||

'''Menu after login''' (headed `--- Logged in as <username> ---`)

||= Option =||= What it does and how to use it =||
|| `[1] View balance` || Shows the available, invested and total USD. ||
|| `[2] Deposit virtual funds` || Enter an amount in USD. It must be a positive number, otherwise you get `Invalid amount.` You get `Deposited 500.0000 USD.` ||
|| `[3] Browse markets` || Same list as before login. ||
|| `[4] Place market BUY order` || Lists all markets, numbered, with their last price. Type the number at `Market #:`. The prototype shows the latest price. Type the quantity. You get `Order executed: buy …` or `Insufficient funds: need …, have …`. ||
|| `[5] Place market SELL order` || Lists only the cryptos you hold, numbered, with columns `Held` and `Free to sell`. Type the number at `Holding #:`, then the quantity. You get `Order executed: sell …` or `Insufficient holding: …`. If you hold nothing, you get `you hold no crypto that is free to sell`. ||
|| `[6] View portfolio` || One row per crypto you hold: quantity, reserved, available, average buy price, current price, value and unrealised P/L. Then your cash, portfolio value and net worth. ||
|| `[7] View transaction history` || Your last 20 ledger entries (deposits, buys, sells), newest first. ||
|| `[8] Manage watchlist` || Opens a submenu: `[1] List items` shows your watchlist with last prices. `[2] Add crypto` lists, numbered, the cryptos not on it yet; type a number. `[3] Remove crypto` lists, numbered, the cryptos on it; type a number. `[0] Back` returns. A user without a watchlist gets one named "Favorites" the first time. ||
|| `[9] Logout` || Back to the first menu. ||
|| `[10] Report: top traders` || P6 report. Enter a start date (inclusive) and an end date (exclusive) as `YYYY-MM-DD`. ||
|| `[11] Report: market performance` || P6 report, with the same two dates. ||
|| `[0] Exit` || Ends the program. ||

=== End-to-end smoke test ===

These values were checked on 2026-09-24 against freshly loaded sample data (PostgreSQL 16.3),
with the bot not running. The expected values are exact.

 1. `./eduberza -init` prints `Schema initialised. Re-run without -init to start the CLI.`
 2. `./eduberza`, then `2` (Login), then `alice` / `test123` gives `Login successful.`
 3. `6` (View portfolio) shows one row: `ETH`, quantity 0.5000, reserved 0.0000, available
    0.5000, average buy 3500.000000, current 3520.000000, value 1760.0000, unrealised P/L
    `+10.0000`. Cash available is 8250.0000 and net worth is 10010.0000.
 4. `4` (BUY). The market list shows `1 ADA`, `2 BTC`, `3 DOGE`, `4 ETH`, `5 SOL`. Type `2` at
    `Market #:`, then `0.01` at `Quantity:`. The result is
    `Order executed: buy 0.0100 BTC @ 67140.000000 (notional 671.4000 USD)`.
 5. `6` (View portfolio) now shows BTC ''and'' ETH, with total value 2431.4000, cash 7578.6000
    (= 8250.00 − 671.40), and net worth still 10010.0000.
 6. `5` (SELL). The holdings list shows `1 BTC` (held 0.0100) and `2 ETH` (held 0.5000). Type
    `2` at `Holding #:`, then `0.5`. The result is
    `Order executed: sell 0.5000 ETH @ 3520.000000 (notional 1760.0000 USD)`.
 7. `7` (View transaction history) lists, newest first: the `sell` (+1760.0000), the `buy` of
    BTC (−671.4000), then the two rows from the sample data, which have the same timestamp:
    `deposit` 10000.0000 "Initial virtual deposit" and `buy` −1750.0000 "Market buy 0.5 ETH @
    3500.00".
 8. `8` (Manage watchlist), then `1` (List items), shows alice's watchlist with BTC, ETH and SOL
    and their last prices. Then `2` (Add crypto) lists `1 ADA` and `2 DOGE`; type `1` and you get
    `Added ADA.` Then `0` (Back).
 9. `9` (Logout), then `0` (Exit).

=== Testing the failure paths ===

These matter more than the happy path, because they prove that the transactions really roll
back and that invalid choices are refused:

 * '''Insufficient funds:''' log in as `charlie` (2500 USD). Choose `4`, market `2` (BTC),
   quantity `1`. Expect `Insufficient funds: need 67140.0000, have 2500.0000` and ''no'' change to
   any table: no order row, no ledger entry, no holding.
 * '''Insufficient holding:''' on fresh data (`./eduberza -load-data`), log in as `alice`. Choose
   `5`; the list shows only `1 ETH` (held 0.5000, free 0.5000). Choose `1`, quantity `5`. Expect
   `Insufficient holding: trying to sell 5.0000, available 0.5000 (of 0.5000 held, 0.0000 reserved)`.
 * '''Nothing to sell:''' as `bob` (no crypto), choose `5`. The holdings list is empty, and you
   get `you hold no crypto that is free to sell` without being asked for a number.
 * '''Invalid choice from a list:''' in any list (for example `8`, then `3` Remove crypto), type a
   number larger than the list. Expect `Invalid choice, enter a number from 1 to N.`
 * '''Invalid deposit:''' choose `2` and enter `-50`. Expect `Invalid amount.`
 * '''Duplicate registration:''' register with username `alice`. Expect
   `Username or email already taken.`
 * '''Invalid e-mail:''' register with an e-mail without `@`. Expect `Invalid email.`
 * '''Wrong password:''' log in as `alice` with any wrong password. Expect
   `Invalid credentials.` An unknown username gives the same message, so the prototype does not
   reveal which accounts exist.

The concurrency guarantee of the sell path (two processes selling the same crypto at the same
moment) cannot be reproduced by typing into two terminals, because each order commits within
milliseconds. It is described in [wiki:UseCase0005Implementation].

=== For the public presentation ===

Demo with `alice`. She already has a position, so the portfolio screen is not empty. Register a
brand-new account live to show UC0001. Run the bot in a background terminal so the prices
visibly move between two portfolio refreshes.

== Editing the ER diagram ==

TerraER is a third-party tool and is '''not''' committed to this repository on purpose. Download
the teacher's build from `https://bazi.finki.ukim.mk/resources/Software/` and run it:

{{{
java -jar TerraER3.11.jar     # then File → Open → docs/P1-ConceptualModel/ERModel_v03.xml
}}}

The current version is `ERModel_v03.xml`. Save new versions as `ERModel_v04.xml` and so on,
and export a matching PNG for each. TerraER does not add the extension itself: type `.xml`
yourself, or the file will not reopen.

== Up-to-date source code ==

The repository is pushed to the FINKI DEVELOP git server. The clone URL and credentials are in
the Repositories section in EPRMS.

=== About the source code ===

 * All the source needed to run the prototype is in this repository: the CLI (`server/`), the
   market bot (`bots/`), the DDL script and the sample-data script (`server/db/`).
 * Third-party Go libraries are '''not''' vendored. `go build` downloads `github.com/lib/pq` at
   the versions pinned in `go.mod` and `go.sum`.
 * Third-party executables are '''not''' committed. `.gitignore` excludes `*.jar`, and TerraER is
   downloaded from the URL above.
 * No third-party images, styles or frameworks are used. The prototype has no images at all;
   the interface is text.
