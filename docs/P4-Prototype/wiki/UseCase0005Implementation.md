= Use-case 0005 Implementation - Place market SELL order =

'''Initiating actor:''' Trader

'''Other actors:''' Market Simulator (indirect — supplies the current price).

A logged-in Trader sells part or all of a holding at the current market price. The
Trader never types a symbol: the system lists only the cryptos the Trader holds and can
still sell (the quantity not already reserved by an open sell order), numbered, with
how much is held and how much is free, and the Trader picks one by its number and
enters the quantity. In one database transaction the system records the order,
reserves the crypto being sold and settles it, credits the proceeds to the Trader's
available cash while reducing the invested cash by the cost basis, writes a ledger
entry and a market trade, and marks the order executed. Cost basis is preserved, so
the realised P/L can be reconstructed from the ledger.

Original use-case description (P3): [wiki:UseCase0005].
Implementation: `server/trade.go`, function
`PlaceOrder(s, "sell")`, which calls `ChooseHolding`, `pickNumber` and `LatestPrice`
from `server/market.go` (the code is shown at the end of this page).

All statements run on the `project` schema (the connection sets
`search_path=project,public` in `server/db/db.go`). The SQL below is copied from the
Go code; only the Go source indentation is removed, a `;` is added after each
statement of the transaction, and `--` comments say what each `$n` placeholder is
bound to.

The run shown is user `alice` right after the buy of
[wiki:UseCase0004Implementation UseCase0004]: 7578.60 USD available, holdings
0.01 BTC (bought at 67140) and 0.5 ETH (bought at 3500). She sells 0.2 ETH.

== Reserve, then settle ==

The crypto being sold is '''reserved''' (`holdings.reserved_quantity`) before it is
removed from the position, and the sell check is against what is truly still free,
`quantity - reserved_quantity`, not against the raw `quantity`, which would also count
crypto already promised to another order. Because only market orders are implemented,
an order settles in the same transaction it is placed in, so reserve and settle are two
statements inside one commit; they stay logically distinct so that a future
limit-order matcher, where an order would stay `open` until a ''later'' transaction fills
it, needs a second transaction but no schema change.

== Scenario ==

 1. '''Trader''' chooses `[5] Place market SELL order` in the authenticated menu (types `5`).
 2. '''System''' prints `-- Place market sell order --` and lists, numbered, only the
    cryptos the Trader holds with some quantity still free to sell, with the quantity
    held, the quantity free to sell and the last price (`ChooseHolding`;
    `$1` = the logged-in user's id):

{{{
SELECT m.id, c.id, c.symbol, m.quote_currency,
       h.quantity, h.quantity - h.reserved_quantity AS free,
       COALESCE(lp.price, 0) AS price
  FROM holdings h
  JOIN crypto  c ON c.id = h.crypto_id
  JOIN markets m ON m.crypto_id = c.id AND m.is_active = true
  LEFT JOIN v_latest_prices lp ON lp.market_id = m.id
 WHERE h.user_id = $1
   AND h.quantity - h.reserved_quantity > 0
 ORDER BY c.symbol
}}}

For alice it prints `1 BTC USD 0.0100 0.0100 67140.000000` and
`2 ETH USD 0.5000 0.5000 3520.000000`, then asks `Holding #:`. Go keeps each row's
market id and crypto id in memory; the Trader only types the list number. (If the
query returns no row, the system prints `you hold no crypto that is free to sell`
and the use-case ends.)

[[Image(uc0005_1_2_holdings.png)]]

 3. '''Trader''' picks the holding by its number in the list: `2` (ETH).
 4. '''System''' takes the market id and crypto id of row 2 from the list and reads the
    latest price of that market (`LatestPrice`; `$1` = the chosen market's id):

{{{
SELECT price FROM v_latest_prices WHERE market_id = $1
}}}

It prints `Latest price for ETH/USD = 3520.000000` and asks `Quantity:`.

[[Image(uc0005_3_4_price.png)]]

 5. '''Trader''' enters the quantity `0.2`.
 6. '''System''' computes in Go notional = quantity × price = 0.2 × 3520 = 704.00 and
    runs one database transaction; the statements are in exactly the order
    `PlaceOrder` executes them for a sell. After statement (b) Go also computes the
    cost basis = avg_price × quantity = 3500 × 0.2 = 700.00 from the locked holding row;
    both values are passed to SQL as parameters.

{{{
BEGIN;

-- (a) record the order as 'open' — no trade has happened yet.
--     $1 = user id, $2 = market id, $3 = side (the Go variable side = 'sell'),
--     $4 = quantity (0.2), $5 = price (3520); the returned id is kept in Go.
INSERT INTO orders (user_id, market_id, side, type, status, quantity, price)
 VALUES ($1, $2, $3, 'market', 'open', $4, $5)
 RETURNING id;

-- (b) lock the holding row and read what is held, what is already reserved and
--     the average entry price. $1 = user id, $2 = crypto id.
--     Go computes available = quantity - reserved_quantity (0.5 - 0 = 0.5);
--     if there is no row or available < quantity -> alternate flow 5a.
SELECT quantity, reserved_quantity, avg_price FROM holdings
  WHERE user_id = $1 AND crypto_id = $2 FOR UPDATE;

-- (c) reserve: committed to this order, not yet removed from the position.
--     $1 = quantity (0.2), $2 = user id, $3 = crypto id.
UPDATE holdings
    SET reserved_quantity = reserved_quantity + $1,
        updated_at        = now()
  WHERE user_id = $2 AND crypto_id = $3;

-- (d) settle: a market order fills immediately, so release the reservation and
--     remove the asset from the position in one step. Same parameters as (c).
UPDATE holdings
    SET quantity          = quantity - $1,
        reserved_quantity = reserved_quantity - $1,
        updated_at        = now()
  WHERE user_id = $2 AND crypto_id = $3;

-- (e) credit the proceeds; reduce invested cash by the cost basis.
--     $1 = notional (704.00), $2 = cost basis (700.00), $3 = user id.
UPDATE users
    SET available_balance = available_balance + $1,
        invested_balance  = GREATEST(invested_balance - $2, 0),
        updated_at        = now()
  WHERE id = $3;

-- (f) ledger entry. $1 = user id, $2 = notional (704.00), $3 = order id from (a),
--     $4 = description built in Go: 'Market sell 0.2000 ETH @ 3520.000000'.
INSERT INTO transactions (user_id, type, amount, currency, related_order, description)
 VALUES ($1, 'sell', $2, 'USD', $3, $4);

-- (g) record the resulting market trade.
--     $1 = market id, $2 = price, $3 = quantity, $4 = side ('sell').
INSERT INTO market_trades (market_id, executed_at, price, quantity, side, source)
 VALUES ($1, now(), $2, $3, $4, 'user');

-- (h) settle the order itself — it has now actually been filled. $1 = order id.
UPDATE orders SET status = 'executed', executed_at = now() WHERE id = $1;

COMMIT;
}}}

 7. '''System''' confirms
    `Order executed: sell 0.2000 ETH @ 3520.000000 (notional 704.0000 USD)` and shows
    the authenticated menu again.

The screenshot shows steps 5–7: the entered quantity, the confirmation and the menu.

[[Image(uc0005_5_7_executed.png)]]

After this run the database holds for alice: ETH `quantity` 0.3000 with
`reserved_quantity` 0.0000; `available_balance` 8282.60 (= 7578.60 + 704.00) and
`invested_balance` 1721.40 (= 2421.40 − 700.00); a `sell` row in `transactions` with
amount 704.0000 and description `Market sell 0.2000 ETH @ 3520.000000`; and the order
with status `executed`. The realised P/L of this sell is notional − cost basis =
704.00 − 700.00 = +4.00 USD.

=== Alternate flow 5a — insufficient holding ===

Right after the sell above, alice chooses `[5]` again. The list from step 2 now shows
`2 ETH USD 0.3000 0.3000 3520.000000`. She picks `2` (ETH) and enters quantity `5`.
In the transaction, statement (a) inserts the `open` order and statement (b) returns
quantity 0.3000 and reserved_quantity 0.0000, so available = 0.3 < 5. `PlaceOrder`
prints

{{{
Insufficient holding: trying to sell 5.0000, available 0.3000 (of 0.3000 held, 0.0000 reserved)
}}}

and returns without running (c)–(h); the deferred `tx.Rollback()` undoes statement (a)
as well, so no order, no reservation and no ledger entry is left behind. The
authenticated menu is shown again. The same message is printed if the holding row no
longer exists (for example because it was sold out from another session after the
list was shown).

[[Image(uc0005_5a_insufficient.png)]]

== Reserve and settle, step by step ==

The CLI reserves and settles inside one transaction, so `reserved_quantity` is never
nonzero ''outside'' a transaction. The intermediate state is shown by running statements
(c) and (d) by hand in one `psql` transaction (which sees its own uncommitted
writes) against alice's ETH holding after the scenario above (0.3 ETH), for a sell of
0.1, and rolling back at the end so nothing is changed. Literal values replace the
`$n` parameters; `:alice` and `:eth` are psql variables for
`(SELECT id FROM users WHERE username = 'alice')` and
`(SELECT id FROM crypto WHERE symbol = 'ETH')`:

{{{
BEGIN;
SELECT quantity, reserved_quantity, quantity - reserved_quantity AS available
  FROM holdings WHERE user_id = :alice AND crypto_id = :eth;
--  quantity | reserved_quantity | available
-- ----------+-------------------+-----------
--    0.3000 |            0.0000 |    0.3000

-- (c) reserve 0.1: the order is placed, no trade has happened yet
UPDATE holdings SET reserved_quantity = reserved_quantity + 0.1, updated_at = now()
 WHERE user_id = :alice AND crypto_id = :eth;
SELECT quantity, reserved_quantity, quantity - reserved_quantity AS available
  FROM holdings WHERE user_id = :alice AND crypto_id = :eth;
--  quantity | reserved_quantity | available
-- ----------+-------------------+-----------
--    0.3000 |            0.1000 |    0.2000

-- (d) settle: the reservation is released and the asset removed
UPDATE holdings SET quantity = quantity - 0.1, reserved_quantity = reserved_quantity - 0.1, updated_at = now()
 WHERE user_id = :alice AND crypto_id = :eth;
SELECT quantity, reserved_quantity, quantity - reserved_quantity AS available
  FROM holdings WHERE user_id = :alice AND crypto_id = :eth;
--  quantity | reserved_quantity | available
-- ----------+-------------------+-----------
--    0.2000 |            0.0000 |    0.2000
ROLLBACK;
}}}

The middle state is what every other connection would see for as long as an order
stayed `open` once limit orders exist: 0.1 ETH still owned but no longer free to sell.

== Two concurrent sells ==

A Trader must not be able to sell the same units twice from two sessions at once. Both
sessions may have listed the holding as free (step 2 runs outside the transaction), so
the protection is statement (b): `SELECT ... FOR UPDATE` locks the holding row, and a
second transaction that reaches (b) waits until the first one commits, then reads the
already reduced `quantity` before deciding.

This was checked with two `psql` sessions running statements (b)–(d) against alice's
0.3 ETH. Session A locked the row, reserved and settled 0.2 ETH and committed after a
3-second pause; session B asked for the lock one second after A had taken it:

{{{
A: SELECT ... FOR UPDATE  ->  quantity 0.3000, reserved_quantity 0.0000
A: reserve 0.2, settle 0.2, pg_sleep(3)
B: 11:43:54  SELECT ... FOR UPDATE   -- blocks, A holds the row lock
A: 11:43:56  COMMIT
B: 11:43:56  lock granted  ->  quantity 0.1000, reserved_quantity 0.0000
}}}

Session B was blocked for the two seconds until A committed and then saw only
0.1 ETH, so a second 0.2 ETH sell in B takes alternate flow 5a
(`available 0.1000`) instead of selling units that no longer exist. (B was rolled
back and alice's holding was restored to 0.3 ETH after the check.)

== The constraint holds even if the application code did not ==

`schema_creation.sql` declares
`CHECK (reserved_quantity >= 0 AND reserved_quantity <= quantity)` on
`holdings.reserved_quantity`, so an inconsistent reservation is impossible at the
database level, independently of `trade.go` (run inside a transaction that was
rolled back):

{{{
UPDATE holdings SET reserved_quantity = quantity + 1 WHERE user_id = :alice AND crypto_id = :eth;
ERROR:  new row for relation "holdings" violates check constraint "holdings_check"
}}}

== Source code ==

`server/trade.go` — `PlaceOrder` (buy and sell):

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
}}}

`server/market.go` — `pickNumber`, `ChooseHolding` and `LatestPrice`:

{{{
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

// ChooseHolding lists only the markets the user can sell in — cryptos they
// hold with some quantity still free (not reserved by an open sell order) —
// with how much is held and free, and lets them pick one by number.
func ChooseHolding(s *Session) (*Market, error) {
	rows, err := db.DB.Query(`
		SELECT m.id, c.id, c.symbol, m.quote_currency,
		       h.quantity, h.quantity - h.reserved_quantity AS free,
		       COALESCE(lp.price, 0) AS price
		  FROM holdings h
		  JOIN crypto  c ON c.id = h.crypto_id
		  JOIN markets m ON m.crypto_id = c.id AND m.is_active = true
		  LEFT JOIN v_latest_prices lp ON lp.market_id = m.id
		 WHERE h.user_id = $1
		   AND h.quantity - h.reserved_quantity > 0
		 ORDER BY c.symbol`, s.UserID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	fmt.Println()
	fmt.Printf("  %-4s  %-8s  %-5s  %12s  %12s  %15s\n", "#", "Symbol", "Quote", "Held", "Free to sell", "Last price")
	fmt.Println("  -------------------------------------------------------------------")
	var list []Market
	for rows.Next() {
		var m Market
		var held, free, price float64
		if err := rows.Scan(&m.ID, &m.CryptoID, &m.Symbol, &m.Quote, &held, &free, &price); err != nil {
			return nil, err
		}
		list = append(list, m)
		fmt.Printf("  %-4d  %-8s  %-5s  %12.4f  %12.4f  %15.6f\n", len(list), m.Symbol, m.Quote, held, free, price)
	}
	if len(list) == 0 {
		return nil, fmt.Errorf("you hold no crypto that is free to sell")
	}
	k, err := pickNumber("Holding #: ", len(list))
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
