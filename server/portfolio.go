package main

import (
	"fmt"

	"bp_project/server/db"
)

// ShowPortfolio - UC0006
// Uses the v_portfolio view to list holdings with current market value and P&L.
func ShowPortfolio(s *Session) {
	rows, err := db.DB.Query(
		`SELECT symbol,
		        quantity,
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

	fmt.Println()
	fmt.Printf("  %-8s  %12s  %14s  %14s  %14s  %14s\n",
		"Symbol", "Quantity", "Avg buy", "Current", "Value", "Unrealised P/L")
	fmt.Println("  ------------------------------------------------------------------------------------")

	var totalValue, totalPnL float64
	empty := true
	for rows.Next() {
		var sym string
		var qty, avg, cur, val, pnl float64
		if err := rows.Scan(&sym, &qty, &avg, &cur, &val, &pnl); err != nil {
			fmt.Println("scan error:", err)
			return
		}
		fmt.Printf("  %-8s  %12.4f  %14.6f  %14.6f  %14.4f  %+14.4f\n",
			sym, qty, avg, cur, val, pnl)
		totalValue += val
		totalPnL += pnl
		empty = false
	}
	if empty {
		fmt.Println("  (no holdings yet)")
		return
	}
	fmt.Println("  ------------------------------------------------------------------------------------")
	fmt.Printf("  %-8s  %12s  %14s  %14s  %14.4f  %+14.4f\n",
		"TOTAL", "", "", "", totalValue, totalPnL)

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
