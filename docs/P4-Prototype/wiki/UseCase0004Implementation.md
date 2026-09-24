= Use-case 0004 Implementation - Place market BUY order =

'''Initiating actor:''' Trader

'''Other actors:''' Market Simulator (indirect — supplies the current price via `market_trades`).

A logged-in Trader buys a crypto asset at the current market price. The Trader never
types a symbol or an identifier: the system lists the active markets with their last
price, numbered, and the Trader picks one by its number and then enters only the
quantity. The system checks that the Trader has enough available cash for
quantity × price and then, in one database transaction, records the order, moves the
cash from available to invested, adds the crypto to the Trader's holding (recomputing
the weighted-average entry price), writes a ledger entry and a market trade, and marks
the order executed. The operation touches five tables (`orders`, `users`, `holdings`,
`transactions`, `market_trades`) and either all of it succeeds or all of it is rolled
back.

Original use-case description (P3): [wiki:UseCase0004].
Implementation: `server/trade.go`, function
`PlaceOrder(s, "buy")` (with `upsertHoldingOnBuy` in the same file), which calls
`ChooseMarket`, `ListMarkets`, `pickNumber` and `LatestPrice` from
`server/market.go` (the code is shown at the end of this page).

All statements run on the `project` schema: the connection sets
`search_path=project,public` (`server/db/db.go`), so `orders` means `project.orders`.
The SQL below is copied from the Go code; only the Go source indentation is removed,
a `;` is added after each statement of the transaction, and `--` comments say what
each `$n` placeholder is bound to.

The run shown is user `alice` on the seed data (available 8250.00 USD, holding
0.5 ETH bought at 3500), buying 0.01 BTC.

== Scenario ==

 1. '''Trader''' chooses `[4] Place market BUY order` in the authenticated menu (types `4`).
 2. '''System''' prints `-- Place market buy order --` and lists all active markets,
    numbered, with their last price (`ListMarkets`, called by `ChooseMarket`):

{{{
SELECT m.id, c.id, c.symbol, m.quote_currency,
       COALESCE(lp.price, 0) AS price
  FROM markets m
  JOIN crypto  c  ON c.id = m.crypto_id
  LEFT JOIN v_latest_prices lp ON lp.market_id = m.id
 WHERE m.is_active = true
 ORDER BY c.symbol
}}}

The rows are printed in this order as `1 ADA`, `2 BTC`, `3 DOGE`, `4 ETH`, `5 SOL`;
Go keeps each row's market id and crypto id in memory, so the Trader only ever sees
and types the list number. The system then asks `Market #:`.

[[Image(uc0004_1_2_markets.png)]]

 3. '''Trader''' picks the market by its number in the list: `2` (BTC/USD).
 4. '''System''' takes the market id and crypto id of row 2 from the list (no further
    lookup by symbol) and reads the latest price of that market (`LatestPrice`;
    `$1` = the chosen market's id):

{{{
SELECT price FROM v_latest_prices WHERE market_id = $1
}}}

It prints `Latest price for BTC/USD = 67140.000000` and asks `Quantity:`.

[[Image(uc0004_3_4_price.png)]]

 5. '''Trader''' enters the quantity `0.01`.
 6. '''System''' computes in Go notional = quantity × price = 0.01 × 67140 = 671.40 and
    passes it to SQL as a parameter. It then runs one database transaction; the
    statements below are in exactly the order `PlaceOrder` executes them for a buy:

{{{
BEGIN;

-- (a) record the order as 'open' — no trade has happened yet.
--     $1 = user id, $2 = market id, $3 = side (the Go variable side = 'buy'),
--     $4 = quantity (0.01), $5 = price (67140); the returned id is kept in Go.
INSERT INTO orders (user_id, market_id, side, type, status, quantity, price)
 VALUES ($1, $2, $3, 'market', 'open', $4, $5)
 RETURNING id;

-- (b) lock the user's row and read the available cash. $1 = user id.
--     Go compares it with the notional; if it is smaller -> alternate flow 6a.
SELECT available_balance FROM users WHERE id = $1 FOR UPDATE;

-- (c) move the notional from available to invested cash.
--     $1 = notional (671.40), $2 = user id.
UPDATE users
    SET available_balance = available_balance - $1,
        invested_balance  = invested_balance  + $1,
        updated_at        = now()
  WHERE id = $2;

-- (d) add the crypto to the holding (upsertHoldingOnBuy), recomputing the
--     weighted-average entry price in the database. Every SET expression sees
--     the pre-update row, so holdings.quantity is still the old quantity.
--     $1 = user id, $2 = crypto id, $3 = quantity (0.01), $4 = price (67140).
INSERT INTO holdings (user_id, crypto_id, quantity, avg_price, updated_at)
 VALUES ($1, $2, $3, $4, now())
 ON CONFLICT (user_id, crypto_id) DO UPDATE
    SET avg_price  = (holdings.quantity * holdings.avg_price
                       + EXCLUDED.quantity * EXCLUDED.avg_price)
                     / (holdings.quantity + EXCLUDED.quantity),
        quantity   = holdings.quantity + EXCLUDED.quantity,
        updated_at = now();

-- (e) ledger entry. $1 = user id, $2 = -notional (-671.40), $3 = order id from (a),
--     $4 = description built in Go: 'Market buy 0.0100 BTC @ 67140.000000'.
INSERT INTO transactions (user_id, type, amount, currency, related_order, description)
 VALUES ($1, 'buy', $2, 'USD', $3, $4);

-- (f) record the resulting market trade.
--     $1 = market id, $2 = price, $3 = quantity, $4 = side ('buy').
INSERT INTO market_trades (market_id, executed_at, price, quantity, side, source)
 VALUES ($1, now(), $2, $3, $4, 'user');

-- (g) settle the order itself — it has now actually been filled. $1 = order id.
UPDATE orders SET status = 'executed', executed_at = now() WHERE id = $1;

COMMIT;
}}}

A buy never reserves crypto (only a sell does, see
[wiki:UseCase0005Implementation UseCase0005]), so `holdings.reserved_quantity` is not
touched and stays 0.

 7. '''System''' confirms
    `Order executed: buy 0.0100 BTC @ 67140.000000 (notional 671.4000 USD)` and shows
    the authenticated menu again.

The screenshot shows steps 5–7: the entered quantity, the confirmation and the menu.

[[Image(uc0004_5_7_executed.png)]]

=== Verification — portfolio after the buy ===

Right after the buy the Trader chooses `[6] View portfolio`
([wiki:UseCase0006Implementation UseCase0006]). It shows the new holding
`BTC 0.0100` with average buy price and current price 67140.000000 (value 671.4000),
the unchanged `ETH 0.5000` (average 3500, current 3520, unrealised P/L +10.0000),
`Cash available : 7578.6000 USD` (= 8250.00 − 671.40), portfolio value 2431.4000 and
net worth 10010.0000 USD. The `Reserved` column is 0.0000 on both rows — a buy never
reserves anything.

[[Image(uc0004_verify_portfolio.png)]]

=== Alternate flow 6a — insufficient funds ===

User `charlie` (seed data: 2500.00 USD available, no crypto) chooses `[4]`, picks
market `2` (BTC, 67140.000000) and enters quantity `1`. Go computes the notional
67140.00. In the transaction, statement (a) inserts the `open` order and statement (b)
`SELECT available_balance FROM users WHERE id = $1 FOR UPDATE` returns 2500.00, which
is less than the notional. `PlaceOrder` prints
`Insufficient funds: need 67140.0000, have 2500.0000` and returns without running
(c)–(g); the deferred `tx.Rollback()` undoes statement (a), so no order, no ledger
entry and no balance change is left behind (after this run charlie has no row in
`orders` and still 2500.00 USD available). The authenticated menu is shown again.

[[Image(uc0004_6a_insufficient.png)]]

=== Alternate flow 3a — number not in the list ===

If in step 3 the Trader enters something that is not a number from 1 to the number of
listed markets, `pickNumber` prints `Invalid choice, enter a number from 1 to 5.`, no
further SQL is run and the authenticated menu is shown again (the same check is shown
in [wiki:UseCase0007Implementation UseCase0007], alternate flow 12a). Likewise, a
quantity that is not a positive number in step 5 prints `Invalid quantity.` before any
transaction is opened.

== Source code ==

`server/trade.go` — `PlaceOrder` (buy and sell) and `upsertHoldingOnBuy`:

{{{
// PlaceOrder - UC0004 (buy) / UC0005 (sell)
// Market order that executes immediately against the latest price.
// Runs inside a single database transaction so the orders, holdings,
// users.balance and transactions tables always agree.
//
// The order still passes through 'open' before 'executed'. Placing it
// reserves whatever it commits — on a sell, the crypto being sold, tracked in
// holdings.reserved_quantity — before anything is actually moved, so a
// second order against the same holding can never be granted the same units
// twice. Because only market orders are implemented, reserve and settle
// happen inside this one transaction rather than across two commits; a
// future limit-order matcher would split them into a second transaction
// later, without needing a schema change.
func PlaceOrder(s *Session, side string) {
	if side != "buy" && side != "sell" {
		fmt.Println("Invalid side.")
		return
	}
	fmt.Printf("\n-- Place market %s order --\n", side)

	// buy: any market; sell: only what the user holds and can still sell
	var m *Market
	var err error
	if side == "buy" {
		m, err = ChooseMarket()
	} else {
		m, err = ChooseHolding(s)
	}
	if err != nil {
		fmt.Println(err)
		return
	}
	price, err := LatestPrice(m.ID)
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Printf("Latest price for %s/%s = %.6f\n", m.Symbol, m.Quote, price)

	qtyStr := prompt("Quantity: ")
	qty, err := strconv.ParseFloat(qtyStr, 64)
	if err != nil || qty <= 0 {
		fmt.Println("Invalid quantity.")
		return
	}
	notional := qty * price

	tx, err := db.DB.Begin()
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	defer tx.Rollback()

	// 1. record the order as 'open' — no trade has happened yet.
	var orderID string
	err = tx.QueryRow(
		`INSERT INTO orders (user_id, market_id, side, type, status, quantity, price)
		 VALUES ($1, $2, $3, 'market', 'open', $4, $5)
		 RETURNING id`,
		s.UserID, m.ID, side, qty, price,
	).Scan(&orderID)
	if err != nil {
		fmt.Println("Error creating order:", err)
		return
	}

	if side == "buy" {
		// check balance
		var avail float64
		if err := tx.QueryRow(
			`SELECT available_balance FROM users WHERE id = $1 FOR UPDATE`,
			s.UserID).Scan(&avail); err != nil {
			fmt.Println("Error:", err)
			return
		}
		if avail < notional {
			fmt.Printf("Insufficient funds: need %.4f, have %.4f\n", notional, avail)
			return
		}

		// debit balance
		if _, err := tx.Exec(
			`UPDATE users
			    SET available_balance = available_balance - $1,
			        invested_balance  = invested_balance  + $1,
			        updated_at        = now()
			  WHERE id = $2`,
			notional, s.UserID,
		); err != nil {
			fmt.Println("Error:", err)
			return
		}

		// a buy never reserves crypto, only ever adds it — upsert holding
		// with running weighted average
		if err := upsertHoldingOnBuy(tx, s.UserID, m.CryptoID, qty, price); err != nil {
			fmt.Println("Error updating holding:", err)
			return
		}

		// ledger entry
		if _, err := tx.Exec(
			`INSERT INTO transactions (user_id, type, amount, currency, related_order, description)
			 VALUES ($1, 'buy', $2, 'USD', $3, $4)`,
			s.UserID, -notional, orderID,
			fmt.Sprintf("Market buy %.4f %s @ %.6f", qty, m.Symbol, price),
		); err != nil {
			fmt.Println("Error:", err)
			return
		}
	} else {
		// sell: lock the holding and check what is actually free to sell —
		// quantity minus whatever another open order has already reserved.
		var held, reserved, avgPrice float64
		err := tx.QueryRow(
			`SELECT quantity, reserved_quantity, avg_price FROM holdings
			  WHERE user_id = $1 AND crypto_id = $2 FOR UPDATE`,
			s.UserID, m.CryptoID,
		).Scan(&held, &reserved, &avgPrice)
		if err != nil && err != sql.ErrNoRows {
			fmt.Println("Error:", err)
			return
		}
		available := held - reserved
		if err == sql.ErrNoRows || available < qty {
			fmt.Printf("Insufficient holding: trying to sell %.4f, available %.4f (of %.4f held, %.4f reserved)\n",
				qty, available, held, reserved)
			return
		}

		// reserve: committed to this order, not yet removed from the position.
		if _, err := tx.Exec(
			`UPDATE holdings
			    SET reserved_quantity = reserved_quantity + $1,
			        updated_at        = now()
			  WHERE user_id = $2 AND crypto_id = $3`,
			qty, s.UserID, m.CryptoID,
		); err != nil {
			fmt.Println("Error:", err)
			return
		}

		// settle: a market order fills immediately, so release the
		// reservation and remove the asset from the position in one step.
		if _, err := tx.Exec(
			`UPDATE holdings
			    SET quantity          = quantity - $1,
			        reserved_quantity = reserved_quantity - $1,
			        updated_at        = now()
			  WHERE user_id = $2 AND crypto_id = $3`,
			qty, s.UserID, m.CryptoID,
		); err != nil {
			fmt.Println("Error:", err)
			return
		}

		// credit balance; reduce invested by cost basis (avg_price * qty)
		costBasis := avgPrice * qty
		if _, err := tx.Exec(
			`UPDATE users
			    SET available_balance = available_balance + $1,
			        invested_balance  = GREATEST(invested_balance - $2, 0),
			        updated_at        = now()
			  WHERE id = $3`,
			notional, costBasis, s.UserID,
		); err != nil {
			fmt.Println("Error:", err)
			return
		}

		// ledger entry
		if _, err := tx.Exec(
			`INSERT INTO transactions (user_id, type, amount, currency, related_order, description)
			 VALUES ($1, 'sell', $2, 'USD', $3, $4)`,
			s.UserID, notional, orderID,
			fmt.Sprintf("Market sell %.4f %s @ %.6f", qty, m.Symbol, price),
		); err != nil {
			fmt.Println("Error:", err)
			return
		}
	}

	// record the resulting market trade so the book reflects this fill
	if _, err := tx.Exec(
		`INSERT INTO market_trades (market_id, executed_at, price, quantity, side, source)
		 VALUES ($1, now(), $2, $3, $4, 'user')`,
		m.ID, price, qty, side,
	); err != nil {
		fmt.Println("Error:", err)
		return
	}

	// settle the order itself: it has now actually been filled.
	if _, err := tx.Exec(
		`UPDATE orders SET status = 'executed', executed_at = now() WHERE id = $1`,
		orderID,
	); err != nil {
		fmt.Println("Error:", err)
		return
	}

	if err := tx.Commit(); err != nil {
		fmt.Println("Commit error:", err)
		return
	}
	fmt.Printf("Order executed: %s %.4f %s @ %.6f (notional %.4f USD)\n",
		side, qty, m.Symbol, price, notional)
}

// upsertHoldingOnBuy creates or updates a holding using running weighted-average price.
//
// This is a single statement that relies on UNIQUE (user_id, crypto_id): the new
// weighted average is recomputed by the database in numeric arithmetic rather
// than in Go float64, and no separate SELECT ... FOR UPDATE round-trip is
// needed because ON CONFLICT DO UPDATE locks the conflicting row itself.
// Every SET expression sees the pre-update row, so `holdings.quantity` below is
// still the old quantity while the average is being computed.
func upsertHoldingOnBuy(tx *sql.Tx, userID, cryptoID string, qty, price float64) error {
	_, err := tx.Exec(
		`INSERT INTO holdings (user_id, crypto_id, quantity, avg_price, updated_at)
		 VALUES ($1, $2, $3, $4, now())
		 ON CONFLICT (user_id, crypto_id) DO UPDATE
		    SET avg_price  = (holdings.quantity * holdings.avg_price
		                       + EXCLUDED.quantity * EXCLUDED.avg_price)
		                     / (holdings.quantity + EXCLUDED.quantity),
		        quantity   = holdings.quantity + EXCLUDED.quantity,
		        updated_at = now()`,
		userID, cryptoID, qty, price,
	)
	return err
}
}}}

`server/market.go` — `ListMarkets`, `pickNumber`, `ChooseMarket` and `LatestPrice`:

{{{
// ListMarkets prints all active markets, numbered, with their latest price,
// and returns them in the printed order so a caller can pick one by number.
func ListMarkets() []Market {
	rows, err := db.DB.Query(`
		SELECT m.id, c.id, c.symbol, m.quote_currency,
		       COALESCE(lp.price, 0) AS price
		  FROM markets m
		  JOIN crypto  c  ON c.id = m.crypto_id
		  LEFT JOIN v_latest_prices lp ON lp.market_id = m.id
		 WHERE m.is_active = true
		 ORDER BY c.symbol`)
	if err != nil {
		fmt.Println("Error:", err)
		return nil
	}
	defer rows.Close()

	fmt.Println()
	fmt.Printf("  %-4s  %-8s  %-5s  %15s\n", "#", "Symbol", "Quote", "Last price")
	fmt.Println("  -----------------------------------------")
	var list []Market
	for rows.Next() {
		var m Market
		var price float64
		if err := rows.Scan(&m.ID, &m.CryptoID, &m.Symbol, &m.Quote, &price); err != nil {
			fmt.Println("scan error:", err)
			return nil
		}
		list = append(list, m)
		fmt.Printf("  %-4d  %-8s  %-5s  %15.6f\n", len(list), m.Symbol, m.Quote, price)
	}
	return list
}

// pickNumber reads a 1-based choice from a list of n items.
func pickNumber(label string, n int) (int, error) {
	if n == 0 {
		return 0, fmt.Errorf("Nothing to choose from.")
	}
	k, err := strconv.Atoi(prompt(label))
	if err != nil || k < 1 || k > n {
		return 0, fmt.Errorf("Invalid choice, enter a number from 1 to %d.", n)
	}
	return k - 1, nil
}

// ChooseMarket lists the active markets and lets the user pick one by its
// number in the list.
func ChooseMarket() (*Market, error) {
	list := ListMarkets()
	k, err := pickNumber("Market #: ", len(list))
	if err != nil {
		return nil, err
	}
	return &list[k], nil
}

// LatestPrice returns the last traded price on a market.
func LatestPrice(marketID string) (float64, error) {
	var price float64
	err := db.DB.QueryRow(
		`SELECT price FROM v_latest_prices WHERE market_id = $1`, marketID,
	).Scan(&price)
	if err == sql.ErrNoRows {
		return 0, fmt.Errorf("no trades yet for this market")
	}
	return price, err
}
}}}
