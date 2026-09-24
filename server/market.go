package main

import (
	"database/sql"
	"fmt"
	"strconv"

	"bp_project/server/db"
)

// Market represents a trading pair.
type Market struct {
	ID       string
	CryptoID string
	Symbol   string
	Quote    string
}

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
