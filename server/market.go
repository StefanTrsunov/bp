package main

import (
	"database/sql"
	"fmt"

	"bp_project/server/db"
)

// Market represents a trading pair.
type Market struct {
	ID       string
	CryptoID string
	Symbol   string
	Quote    string
}

// ListMarkets prints all active markets with their latest price.
func ListMarkets() {
	rows, err := db.DB.Query(`
		SELECT m.id, c.symbol, m.quote_currency,
		       COALESCE(lp.price, 0) AS price
		  FROM markets m
		  JOIN crypto  c  ON c.id = m.crypto_id
		  LEFT JOIN v_latest_prices lp ON lp.market_id = m.id
		 WHERE m.is_active = true
		 ORDER BY c.symbol`)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	defer rows.Close()

	fmt.Println()
	fmt.Printf("  %-4s  %-8s  %-5s  %15s\n", "#", "Symbol", "Quote", "Last price")
	fmt.Println("  -----------------------------------------")
	i := 1
	for rows.Next() {
		var id, sym, quote string
		var price float64
		if err := rows.Scan(&id, &sym, &quote, &price); err != nil {
			fmt.Println("scan error:", err)
			return
		}
		fmt.Printf("  %-4d  %-8s  %-5s  %15.6f\n", i, sym, quote, price)
		i++
	}
}

// ChooseMarket asks the user to pick a market by symbol and returns it.
func ChooseMarket() (*Market, error) {
	ListMarkets()
	sym := prompt("Market symbol (e.g. BTC): ")
	if sym == "" {
		return nil, fmt.Errorf("no symbol entered")
	}
	var m Market
	err := db.DB.QueryRow(`
		SELECT m.id, c.id, c.symbol, m.quote_currency
		  FROM markets m
		  JOIN crypto c ON c.id = m.crypto_id
		 WHERE upper(c.symbol) = upper($1)
		   AND m.is_active = true
		 LIMIT 1`, sym,
	).Scan(&m.ID, &m.CryptoID, &m.Symbol, &m.Quote)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("market %s not found", sym)
	}
	if err != nil {
		return nil, err
	}
	return &m, nil
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
