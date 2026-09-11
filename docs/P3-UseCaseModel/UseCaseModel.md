= Use-case model =

The detailed pages for this phase are kept in the project's GitHub repository,
[https://github.com/StefanTrsunov/bp StefanTrsunov/bp], under `docs/P3-UseCaseModel/`. Every
use-case link below opens the corresponding file there.

== Actors / Roles ==

'''Visitor''' – Anyone using EduBerza without an account, who can look at public market
information, create an account, and log in.

'''Trader''' – A registered, logged-in user who deposits virtual funds, places market buy and
sell orders, follows the value of their portfolio, and keeps a watchlist of assets they want to
monitor.

'''Market Simulator''' – An external automated system (the bot in `bots/`) that writes simulated
trades and candles into the database so prices move without a connection to a real exchange.

== Use-Cases ==

=== Visitor ===

 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0001.md UC0001] –
   '''Register new account''' – Visitor creates an account with a unique username and e-mail; the
   password is stored as a SHA-256 hash.
 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0002.md UC0002] –
   '''Log in''' – Visitor authenticates with username and password so the system treats every
   following action as a Trader.

=== Trader ===

 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0003.md UC0003] –
   '''Deposit virtual funds''' – Trader tops up their virtual cash balance; the user row and the
   ledger are written in one transaction.
 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0004.md UC0004] –
   '''Place market BUY order''' – Trader buys a crypto asset at the current market price, which
   debits cash and upserts the holding at a running weighted-average price.
 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0005.md UC0005] –
   '''Place market SELL order''' – Trader sells part or all of a holding at the current market
   price, which credits cash and preserves the cost basis.
 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0006.md UC0006] –
   '''View portfolio and transaction history''' – Trader inspects current holdings, unrealised
   P/L, cash balances and the most recent ledger entries.
 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0007.md UC0007] –
   '''Manage watchlist''' – Trader lists, adds and removes crypto assets on a personal watchlist,
   where adding an asset already on the list is a no-op.

=== Market Simulator ===

The Market Simulator initiates no use case of its own. It participates in
[https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0004.md UC0004] and
[https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0005.md UC0005]
indirectly, by keeping `project.market_trades` populated so that `project.v_latest_prices`
returns a current price for every active market.

== Use-case model diagram ==

{{{#!comment
The diagram is optional for P3. Commit the exported image to
docs/P3-UseCaseModel/use_case_diagram.png and then replace this comment with:

[https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/use_case_diagram.png Use-case model diagram]
}}}

== Detailed Use-Cases ==

The following use-cases are documented in detail, with SQL tested against the P2 database:

 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0001.md UseCase0001] – Visitor registers a new account
 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0002.md UseCase0002] – Visitor logs in
 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0003.md UseCase0003] – Trader deposits virtual funds
 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0004.md UseCase0004] – Trader places a market BUY order
 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0005.md UseCase0005] – Trader places a market SELL order
 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0006.md UseCase0006] – Trader views portfolio and transaction history
 * [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0007.md UseCase0007] – Trader manages a watchlist

== Realization details on selection of the most important use cases ==

This is a solo project, so '''at least 3 use cases''' are required. '''7 use cases''' are
documented, for a safety margin. All seven are implemented in the P4 prototype; see
[https://github.com/StefanTrsunov/bp/tree/main/server server/] for the Go source and
[https://github.com/StefanTrsunov/bp/blob/main/docs/P4-Prototype/PrototypeImplementation.md PrototypeImplementation]
for the documented runs.

||=Use case=||=Importance=||=Why it was selected=||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0001.md UC0001 – Register]||High||Nothing else works without it; demonstrates `INSERT` with a uniqueness check.||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0002.md UC0002 – Log in]||High||Authenticates every Trader action; demonstrates `SELECT` with parameter binding.||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0003.md UC0003 – Deposit]||High||Shows a multi-row transaction: `UPDATE users` plus `INSERT INTO transactions`.||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0004.md UC0004 – Buy]||Very high||Core of the exchange: `INSERT orders`, `UPDATE users`, upsert `holdings`, ledger entry, market trade.||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0005.md UC0005 – Sell]||Very high||Dual of Buy; demonstrates row-level `FOR UPDATE` locking and cost-basis bookkeeping.||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0006.md UC0006 – Portfolio]||High||Demonstrates joins over `holdings`, `markets` and `crypto`, and the `v_portfolio` view.||
||[https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCase0007.md UC0007 – Watchlist]||Medium||Demonstrates N–M relation handling and `ON CONFLICT` upsert semantics.||

== AI usage ==

AI was used in this phase and is logged in full, per the course rule for P1 onward.

 * '''Phase log:'''
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P3-UseCaseModel/UseCaseModelAIUsage.md UseCaseModelAIUsage.md]
   – service used, what the AI produced, and what I decided myself.
 * '''Full conversation transcript:'''
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P1-ConceptualModel/ERModelAIUsage.md ERModelAIUsage.md]
   – the same conversation produced the P1–P4 artefacts, so the complete prompt/response log is
   kept in one place. Direct links:
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P1-ConceptualModel/ERModelAIUsage.md#session-1--2026-04-21 Session 1 – 2026-04-21],
   [https://github.com/StefanTrsunov/bp/blob/main/docs/P1-ConceptualModel/ERModelAIUsage.md#session-2--2026-08-06--2026-08-07 Session 2 – 2026-08-06/07].

'''Service:''' Claude Code (Anthropic), https://claude.com/claude-code – Claude subscription,
model Claude Opus 4.7 (1M context).

'''In short:''' the AI proposed the actor taxonomy and drafted the seven use cases with their SQL
in session 1. In session 2 the use-case model itself was '''not''' changed – the only work was
re-executing every scenario, including the failure paths, against a live PostgreSQL 16 database.
