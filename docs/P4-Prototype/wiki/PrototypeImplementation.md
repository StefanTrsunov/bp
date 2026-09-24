= Prototype Implementation =

== Implemented use-cases ==

 * [wiki:UseCase0001Implementation] — Register new account
 * [wiki:UseCase0002Implementation] — Log in
 * [wiki:UseCase0003Implementation] — Deposit virtual funds
 * [wiki:UseCase0004Implementation] — Place market BUY order
 * [wiki:UseCase0005Implementation] — Place market SELL order
 * [wiki:UseCase0006Implementation] — View portfolio and transaction history
 * [wiki:UseCase0007Implementation] — Manage watchlist

Each page follows its P3 use case step by step. It adds the exact SQL the Go code runs in that
step and a screenshot of the step from a real run against the database.

 * How to build, configure, run and test the prototype: [wiki:BuildInstructions]
 * AI usage for this phase: [wiki:PrototypeImplementationAIUsage]

== Overview ==

!EduBerza's P4 prototype is a Go command-line program. It works against the `project` schema in
PostgreSQL. It implements all seven use cases from [wiki:UseCaseModel]; the course asks for at
least three. Every database access is real SQL that was executed and tested. A second program,
the market bot, simulates a live market so prices move while the prototype runs.

The source code is in the project's git repository: the CLI in `server/`, the bot in `bots/`,
and the SQL scripts in `server/db/`.

== Technology and architecture ==

 * '''Language:''' Go (module `bp_project`, `go 1.25` in `go.mod`). The only third-party
   library is the PostgreSQL driver `github.com/lib/pq`.
 * '''Database:''' PostgreSQL. Every table, view and function is in the `project` schema. The
   DDL is `schema_creation.sql` and the sample data is `data_load.sql`. Both scripts are
   compiled into the binary and run by `./eduberza -init`.
 * '''Interface:''' plain text menus on standard input and output. There are no web server,
   frameworks, images or styles.
 * '''Structure:''' one source file per area of the application.

||= File =||= Responsibility =||= Use cases =||
|| `server/main.go` || Flags `-init` / `-load-data`, then starts the menu loop || — ||
|| `server/cli.go` || The two menus (before and after login), input reading || all ||
|| `server/db/db.go` || Connection from `.env` / environment variables, embedded SQL scripts || — ||
|| `server/auth.go` || Register, log in (SHA-256 password hash) || UC0001, UC0002 ||
|| `server/account.go` || Balance, deposit, transaction history || UC0003, UC0006 ||
|| `server/market.go` || Market list, choosing a market or a holding by number, latest price || UC0004, UC0005 ||
|| `server/trade.go` || Market buy and sell orders, each in one transaction || UC0004, UC0005 ||
|| `server/portfolio.go` || Portfolio with current value and unrealised P/L || UC0006 ||
|| `server/watchlist.go` || List, add and remove watchlist items || UC0007 ||
|| `bots/main.go` || Market bot: random-walk price ticks into `market_trades`, 1-minute candles || — ||

== No identifiers to remember ==

The user never has to type or remember an id, a code or a symbol:

 * Every menu is numbered, and the user answers with the number of an option.
 * '''Buying:''' all active markets are listed with their latest price, numbered 1…n. The user
   enters the market's number at `Market #:` (`ChooseMarket` in `market.go`).
 * '''Selling:''' only the cryptos the user actually holds are listed, each with the quantity
   held and the quantity still free to sell. The user enters the holding's number at
   `Holding #:` (`ChooseHolding`). A user who holds nothing free to sell gets
   `you hold no crypto that is free to sell` and is never asked to choose.
 * '''Watchlist:''' ''Add'' lists the cryptos that are not on the watchlist yet. ''Remove''
   lists the ones that are on it. Both are numbered, and the user enters the number.
 * A number outside the list is refused with `Invalid choice, enter a number from 1 to N.` and
   nothing is changed.

The only things the user types are their own data: username, e-mail, full name, password, the
amount to deposit, the quantity to buy or sell, and the date range of the two P6 reports.

== What the prototype demonstrates about the database design ==

 * '''The current price is never stored as a column.''' It is always the price of the most
   recent row in `market_trades`, read through the `v_latest_prices` view. The user's own fills
   and the bot's simulated trades go into the same table, so there is only one definition of
   "the price".
 * '''Money movements are transactional.''' A buy touches five tables (`orders`, `users`,
   `holdings`, `transactions`, `market_trades`) inside one transaction. If the balance check
   fails, the whole transaction is rolled back: after a rejected purchase there is no order
   row, no ledger entry and no holding. The failure-path tests in [wiki:BuildInstructions]
   check this.
 * '''Constraints do real work.''' `UNIQUE (user_id, crypto_id)` on `holdings` is what makes
   the `INSERT … ON CONFLICT DO UPDATE` upsert possible, so the database recomputes the
   weighted-average entry price in one statement, instead of the application reading, changing
   and writing the row. `CHECK (reserved_quantity >= 0 AND reserved_quantity <= quantity)` does
   the same for the sell path: the database itself makes an inconsistent reservation
   impossible, and it does not rely only on `trade.go` being careful.
 * '''Selling reserves before it removes.''' A sell order locks the holding row with
   `SELECT … FOR UPDATE`, reserves the quantity being sold, then settles by removing it (see
   [wiki:UseCase0005Implementation]). Two sell orders for more than the free quantity, placed
   at the same moment from two separate processes, are serialised by the row lock. Exactly one
   of them succeeds. This was tested with two concurrent processes in session 3 (see
   [wiki:PrototypeImplementationAIUsage]).

== Known limitations ==

These were left out on purpose for a first prototype. They belong to the later phases:

 * Only `market` orders execute. The schema accepts `limit` (`orders.type`), but there is no
   matching logic for it.
 * Passwords are hashed with SHA-256 and no salt. That shows the password itself is never
   stored, but it is not good enough for real use. A proper password hash belongs in P9
   (security).
 * Money is `float64` in Go, while the database columns are `numeric`. For that reason, all
   arithmetic that must be exact (the weighted average) is done in SQL. Real use would need a
   decimal type on the Go side too.
 * The prototype sets no connection pool and no explicit isolation level. Both are P8 topics.
 * A reservation only exists inside one transaction, because the prototype only has market
   orders, and they settle immediately. A real limit-order matcher would leave
   `holdings.reserved_quantity` set and `orders.status = 'open'` between two separate commits.
   It would also need a way to cancel an order and release the reservation. Neither is
   implemented, because nothing in the prototype creates an order that stays open.

== History of changes ==

The code started as my own Go backend: HTTP handlers, a draft schema, and a `db.go` that
recreated the tables on every start. It changed as follows. The AI's share of each change is
logged in [wiki:PrototypeImplementationAIUsage].

||= Date =||= Change =||= Origin =||
|| 2026-04-21 || My HTTP backend rewritten as the CLI prototype covering UC0001–UC0007. The schema errors in my draft were corrected. The market bot was added. || My code and decisions (CLI instead of web, drop the frontend, keep a simulator); rewrite by AI (session 1) ||
|| 2026-08-06/07 || Three bugs fixed: path resolution of `.env` and the SQL scripts, an endless loop at end of input, and an error check in the wrong order on the sell path. The holding update became one `INSERT … ON CONFLICT DO UPDATE`. || I asked for a code review; fixes by AI (session 2) ||
|| 2026-09-16 || `holdings.reserved_quantity` added. The sell path now reserves, then settles. Orders go from `open` to `executed`. || The edge case was mine; implementation by AI (session 3) ||
|| 2026-09-24 || Every choice is picked from a numbered list: markets by number, a sell lists only the user's holdings, the watchlist lists the cryptos. All screenshots were retaken, one per step. || I asked for a check against the P4 rules; implementation by AI (session 4) ||

'''Service:''' Claude Code (Anthropic), Claude subscription. Session 1 used Claude Opus 4.7 (1M
context), session 2 Claude Opus 5 (1M context), session 3 Claude Sonnet 5, and session 4
Claude Opus 5.5 (1M context).
