package main

import (
	"database/sql"
	"fmt"
	"strconv"

	"bp_project/server/db"
)

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

	m, err := ChooseMarket()
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
