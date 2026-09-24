= Use-case 0006 Implementation - View portfolio and transaction history =

'''Initiating actor:''' Trader

'''Other actors:''' —

A logged-in Trader inspects the current state of their account. The portfolio view
lists every cryptocurrency the Trader holds with the quantity (also split into the
part reserved by open sell orders and the part that is free to sell), the average
buy price, the current market price, the market value and the unrealised
profit/loss, followed by a totals row and a cash summary (cash available, portfolio
value, net worth). The transaction history lists the Trader's last 20 ledger
entries — deposits, buys and sells — newest first. Both are read-only: nothing in
the database is changed.

Original use-case description (P3): [wiki:UseCase0006].
Implementation: `server/portfolio.go`, function `ShowPortfolio`, and
`server/account.go`, function `ShowTransactions` (the code is shown at the end of
this page).

Precondition: the Trader is logged in ([wiki:UseCase0002Implementation UseCase0002]).
The run below is alice's, after she bought 0.01 BTC
([wiki:UseCase0004Implementation UseCase0004]) and sold 0.2 ETH
([wiki:UseCase0005Implementation UseCase0005]) on top of the seed data (0.5 ETH,
8250.00 USD cash).

== Scenario ==

=== Portfolio ===

 1. '''Trader''' chooses `[6] View portfolio` in the authenticated menu (types `6`).
    The menu is the one shown in [wiki:UseCase0002Implementation UseCase0002], step 7.
 2. '''System''' queries the `v_portfolio` view (`$1` = user id):

{{{
SELECT symbol,
       quantity,
       COALESCE(reserved_quantity, 0),
       COALESCE(available_quantity, quantity),
       COALESCE(avg_price, 0),
       COALESCE(current_price, 0),
       COALESCE(market_value, 0),
       COALESCE(unrealized_pnl, 0)
  FROM v_portfolio
 WHERE user_id = $1 AND quantity > 0
 ORDER BY symbol
}}}

 3. '''System''' displays the rows and a `TOTAL` row (sums of the value and P/L columns,
    computed in Go), then reads the cash balance for the summary (`$1` = user id):

{{{
SELECT available_balance, invested_balance FROM users WHERE id = $1
}}}

and prints `Cash available` (= `available_balance`), `Portfolio value`
(= the total market value) and `Net worth` (= their sum).

The screenshot shows the result of steps 2–3. The table is wider than the
terminal window, so each long line wraps and the header row has scrolled out of
the top of the window; the complete output of this run is reproduced below it.

[[Image(uc0006_portfolio.png)]]

{{{
  Symbol        Quantity      Reserved     Available         Avg buy         Current           Value  Unrealised P/L
  ------------------------------------------------------------------------------------------------------------------
  BTC             0.0100        0.0000        0.0100    67140.000000    67140.000000        671.4000         +0.0000
  ETH             0.3000        0.0000        0.3000     3500.000000     3520.000000       1056.0000         +6.0000
  ------------------------------------------------------------------------------------------------------------------
  TOTAL                                                                                    1727.4000         +6.0000

  Cash available : 8282.6000 USD
  Portfolio value: 1727.4000 USD
  Net worth      : 10010.0000 USD
}}}

Checking the figures: ETH is 0.5 − 0.2 = 0.3 at an average buy price of 3500 and
a current price of 3520, so value 1056.00 and P/L 0.3 × 20 = +6.00; BTC was just
bought at the current price 67140, so its P/L is 0. Cash is
8250.00 − 671.40 (buy) + 704.00 (sell) = 8282.60. `Reserved` is 0.0000 for both
because the market orders executed immediately — a quantity is reserved only
while a sell order is still open.

=== Transaction history ===

 1. '''Trader''' chooses `[7] View transaction history` in the authenticated menu
    (types `7`).
 2. '''System''' queries the last 20 ledger entries of the Trader (`$1` = user id) and
    prints them, newest first (the time is shown as the first 19 characters of
    `created_at`):

{{{
SELECT created_at, type, amount, currency, COALESCE(description, '')
  FROM transactions
 WHERE user_id = $1
 ORDER BY created_at DESC
 LIMIT 20
}}}

The screenshot shows steps 1–2: the choice `7` and the four ledger rows of this
run — the sell of 0.2 ETH (+704.0000 USD), the buy of 0.01 BTC (−671.4000 USD),
and the two seed rows, the initial deposit of 10000.0000 USD and the seed buy of
0.5 ETH (−1750.0000 USD). Buys are stored with a negative amount, deposits and
sells with a positive one. The two seed rows were inserted by `data_load.sql` in
one statement and have the same `created_at`, so their relative order is not
determined by the `ORDER BY`.

[[Image(uc0006_history.png)]]

All statements run on the `project` schema (the connection sets
`search_path=project,public`).

=== Reference — how v_portfolio is defined ===

From `server/db/schema_creation.sql`:

{{{
CREATE OR REPLACE VIEW project.v_portfolio AS
SELECT h.user_id,
       c.symbol,
       h.quantity,
       h.reserved_quantity,
       (h.quantity - h.reserved_quantity) AS available_quantity,
       h.avg_price,
       lp.price                           AS current_price,
       (h.quantity * lp.price)            AS market_value,
       (h.quantity * (lp.price - h.avg_price)) AS unrealized_pnl
FROM   project.holdings h
JOIN   project.crypto   c ON c.id = h.crypto_id
LEFT   JOIN project.markets m ON m.crypto_id = c.id AND m.quote_currency = 'USD'
LEFT   JOIN project.v_latest_prices lp ON lp.market_id = m.id;
}}}

== How to reproduce ==

{{{
./eduberza -init
./eduberza
# [2] Login: alice / test123
# [4] buy 0.01 BTC, [5] sell 0.2 ETH   (UseCase0004 / UseCase0005)
# [6] View portfolio
# [7] View transaction history
}}}

Both screenshots come from one real run (portfolio and history taken right after
the buy and sell runs).

== Source code ==

`server/portfolio.go` — `ShowPortfolio`:

{{{
// ShowPortfolio - UC0006
// Uses the v_portfolio view to list holdings with current market value and P&L.
func ShowPortfolio(s *Session) {
	rows, err := db.DB.Query(
		`SELECT symbol,
		        quantity,
		        COALESCE(reserved_quantity, 0),
		        COALESCE(available_quantity, quantity),
		        COALESCE(avg_price, 0),
		        COALESCE(current_price, 0),
		        COALESCE(market_value, 0),
		        COALESCE(unrealized_pnl, 0)
		   FROM v_portfolio
		  WHERE user_id = $1 AND quantity > 0
		  ORDER BY symbol`,
		s.UserID,
	)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	defer rows.Close()

	header := fmt.Sprintf("  %-8s  %12s  %12s  %12s  %14s  %14s  %14s  %14s",
		"Symbol", "Quantity", "Reserved", "Available", "Avg buy", "Current", "Value", "Unrealised P/L")
	fmt.Println()
	fmt.Println(header)
	fmt.Println("  " + strings.Repeat("-", len(header)-2))

	var totalValue, totalPnL float64
	empty := true
	for rows.Next() {
		var sym string
		var qty, reserved, avail, avg, cur, val, pnl float64
		if err := rows.Scan(&sym, &qty, &reserved, &avail, &avg, &cur, &val, &pnl); err != nil {
			fmt.Println("scan error:", err)
			return
		}
		fmt.Printf("  %-8s  %12.4f  %12.4f  %12.4f  %14.6f  %14.6f  %14.4f  %+14.4f\n",
			sym, qty, reserved, avail, avg, cur, val, pnl)
		totalValue += val
		totalPnL += pnl
		empty = false
	}
	if empty {
		fmt.Println("  (no holdings yet)")
		return
	}
	fmt.Println("  " + strings.Repeat("-", len(header)-2))
	fmt.Printf("  %-8s  %12s  %12s  %12s  %14s  %14s  %14.4f  %+14.4f\n",
		"TOTAL", "", "", "", "", "", totalValue, totalPnL)

	// cash summary
	var avail, invested float64
	_ = db.DB.QueryRow(
		`SELECT available_balance, invested_balance FROM users WHERE id = $1`,
		s.UserID,
	).Scan(&avail, &invested)
	fmt.Printf("\n  Cash available : %.4f USD\n", avail)
	fmt.Printf("  Portfolio value: %.4f USD\n", totalValue)
	fmt.Printf("  Net worth      : %.4f USD\n", avail+totalValue)
}
}}}

`server/account.go` — `ShowTransactions`:

{{{
// ShowTransactions lists the last 20 ledger entries for the user.
func ShowTransactions(s *Session) {
	rows, err := db.DB.Query(
		`SELECT created_at, type, amount, currency, COALESCE(description, '')
		   FROM transactions
		  WHERE user_id = $1
		  ORDER BY created_at DESC
		  LIMIT 20`,
		s.UserID,
	)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	defer rows.Close()

	fmt.Println()
	fmt.Printf("  %-20s  %-8s  %12s  %-3s  %s\n", "When", "Type", "Amount", "Cur", "Description")
	fmt.Println("  " + strings.Repeat("-", 70))
	for rows.Next() {
		var when, typ, cur, desc string
		var amt float64
		if err := rows.Scan(&when, &typ, &amt, &cur, &desc); err != nil {
			fmt.Println("scan error:", err)
			return
		}
		fmt.Printf("  %-20s  %-8s  %12.4f  %-3s  %s\n", when[:19], typ, amt, cur, desc)
	}
}
}}}
