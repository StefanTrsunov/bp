= Use-case model =

The detailed pages for this phase are kept in the project's !GitHub repository,
`https://github.com/StefanTrsunov/bp`, under `docs/P3-UseCaseModel/`. Every
use case below is documented on its own wiki page ([wiki:UseCase0001] to [wiki:UseCase0007]).

== Actors / Roles ==

'''Visitor''' – Anyone using !EduBerza without an account, who can look at public market
information, create an account, and log in.

'''Trader''' – A registered, logged-in user who deposits virtual funds, places market buy and
sell orders, follows the value of their portfolio, and keeps a watchlist of assets they want to
monitor.

'''Market Simulator''' – An external automated system (the bot in `bots/`) that writes simulated
trades and candles into the database so prices move without a connection to a real exchange.

== Use-Cases ==

=== Visitor ===

 * UC0001 –
   '''Register new account''' – Visitor creates an account with a unique username and e-mail; the
   password is stored as a SHA-256 hash.
 * UC0002 –
   '''Log in''' – Visitor authenticates with username and password so the system treats every
   following action as a Trader.

=== Trader ===

 * UC0003 –
   '''Deposit virtual funds''' – Trader tops up their virtual cash balance; the user row and the
   ledger are written in one transaction.
 * UC0004 –
   '''Place market BUY order''' – Trader buys a crypto asset at the current market price, which
   debits cash and upserts the holding at a running weighted-average price.
 * UC0005 –
   '''Place market SELL order''' – Trader sells part or all of a holding at the current market
   price, which reserves the crypto being sold, credits cash and preserves the cost basis.
 * UC0006 –
   '''View portfolio and transaction history''' – Trader inspects current holdings, unrealised
   P/L, cash balances and the most recent ledger entries.
 * UC0007 –
   '''Manage watchlist''' – Trader lists, adds and removes crypto assets on a personal watchlist,
   where adding an asset already on the list is a no-op.

=== Market Simulator ===

The Market Simulator initiates no use case of its own. It participates in
UC0004 and
UC0005
indirectly, by keeping `project.market_trades` populated so that `project.v_latest_prices`
returns a current price for every active market.

== Use-case model diagram ==

{{{#!comment
The diagram is optional for P3. Attach the exported image use_case_diagram.png
to this wiki page and then replace this comment with:

[[Image(use_case_diagram.png)]]
}}}

== Detailed Use-Cases ==

The following use-cases are documented in detail, with SQL tested against the P2 database:

 * [wiki:UseCase0001] – Visitor registers a new account
 * [wiki:UseCase0002] – Visitor logs in
 * [wiki:UseCase0003] – Trader deposits virtual funds
 * [wiki:UseCase0004] – Trader places a market BUY order
 * [wiki:UseCase0005] – Trader places a market SELL order
 * [wiki:UseCase0006] – Trader views portfolio and transaction history
 * [wiki:UseCase0007] – Trader manages a watchlist

== Realization details on selection of the most important use cases ==

This is a solo project, so '''at least 3 use cases''' are required. '''7 use cases''' are
documented, for a safety margin. All seven are implemented in the P4 prototype; see
`server/` for the Go source and
[wiki:PrototypeImplementation]
for the documented runs.

||=Use case=||=Importance=||=Why it was selected=||
||UC0001 – Register||High||Nothing else works without it; demonstrates `INSERT` with a uniqueness check.||
||UC0002 – Log in||High||Authenticates every Trader action; demonstrates `SELECT` with parameter binding.||
||UC0003 – Deposit||High||Shows a multi-row transaction: `UPDATE users` plus `INSERT INTO transactions`.||
||UC0004 – Buy||Very high||Core of the exchange: `INSERT orders`, `UPDATE users`, upsert `holdings`, ledger entry, market trade.||
||UC0005 – Sell||Very high||Dual of Buy; demonstrates row-level `FOR UPDATE` locking, reservation of committed crypto (`holdings.reserved_quantity`) and cost-basis bookkeeping.||
||UC0006 – Portfolio||High||Demonstrates joins over `holdings`, `markets` and `crypto`, and the `v_portfolio` view.||
||UC0007 – Watchlist||Medium||Demonstrates N–M relation handling and `ON CONFLICT` upsert semantics.||

== AI usage ==

AI was used in this phase and is logged in full, per the course rule for P1 onward.

 * '''Phase log:'''
   [wiki:UseCaseModelAIUsage]
   – service used, what the AI produced, and what I decided myself.
 * '''Full conversation transcript:'''
   [wiki:ERModelAIUsage]
   – the same conversation produced the P1–P4 artefacts, so the complete prompt/response log is
   kept in one place. Relevant sections of that page:
   Session 1 – 2026-04-21,
   Session 2 – 2026-08-06/07,
   Session 3 – 2026-09-16.

'''Service:''' Claude Code (Anthropic), `https://claude.com/claude-code` – Claude subscription,
model Claude Opus 4.7 (1M context) in sessions 1–2, Claude Sonnet 5 in session 3.

'''In short:''' the AI proposed the actor taxonomy and drafted the seven use cases with their SQL
in session 1. In session 2 the use-case model itself was '''not''' changed – the only work was
re-executing every scenario, including the failure paths, against a live PostgreSQL 16 database.
In session 3, UC0004 and UC0005 were revised to reserve the resource an order commits (crypto on
a sell) before settling it, closing a gap where nothing stopped a second sell order from being
granted crypto already promised to a first one; see the Session 3 – 2026-09-16 section of
[wiki:UseCaseModelAIUsage].
