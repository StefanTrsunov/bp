package main

import (
	"fmt"
	"strings"
	"time"

	"bp_project/server/db"
)

// promptPeriod reads a [from, to) date range for the P6 reports.
func promptPeriod() (time.Time, time.Time, bool) {
	fromStr := prompt("From, inclusive (YYYY-MM-DD): ")
	toStr := prompt("To, exclusive (YYYY-MM-DD): ")
	from, err1 := time.Parse("2006-01-02", fromStr)
	to, err2 := time.Parse("2006-01-02", toStr)
	if err1 != nil || err2 != nil || !to.After(from) {
		fmt.Println("Invalid date range.")
		return time.Time{}, time.Time{}, false
	}
	return from, to, true
}

// ShowTopTraders - P6 report 1
// Realized trading performance per user over a chosen period, via the
// project.report_top_traders() SQL function (one query, bucketed by quarter
// internally to measure consistency).
func ShowTopTraders(s *Session) {
	fmt.Println("\n-- Top traders report --")
	from, to, ok := promptPeriod()
	if !ok {
		return
	}

	rows, err := db.DB.Query(`SELECT * FROM report_top_traders($1, $2)`, from, to)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	defer rows.Close()

	header := fmt.Sprintf("  %-10s  %14s  %14s  %10s  %6s  %6s  %6s  %10s",
		"Username", "Realized P/L", "Invested", "ROI %", "Prof.", "Loss", "Total", "Consist. %")
	fmt.Println()
	fmt.Println(header)
	fmt.Println("  " + strings.Repeat("-", len(header)-2))

	empty := true
	for rows.Next() {
		var username string
		var realizedPL, invested, roi, consistency float64
		var profitable, losing, total int64
		if err := rows.Scan(&username, &realizedPL, &invested, &roi, &profitable, &losing, &total, &consistency); err != nil {
			fmt.Println("scan error:", err)
			return
		}
		fmt.Printf("  %-10s  %+14.4f  %14.4f  %10.2f  %6d  %6d  %6d  %10.2f\n",
			username, realizedPL, invested, roi, profitable, losing, total, consistency)
		empty = false
	}
	if empty {
		fmt.Println("  (no buy/sell/fee transactions in that range)")
	}
}

// ShowMarketPerformance - P6 report 2
// Trading activity and price behaviour per market over a chosen period, via
// the project.report_market_performance() SQL function.
func ShowMarketPerformance(s *Session) {
	fmt.Println("\n-- Market performance report --")
	from, to, ok := promptPeriod()
	if !ok {
		return
	}

	rows, err := db.DB.Query(`SELECT * FROM report_market_performance($1, $2)`, from, to)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	defer rows.Close()

	header := fmt.Sprintf("  %-6s  %-5s  %12s  %8s  %14s  %12s  %14s  %8s",
		"Symbol", "Quote", "Volume", "Trades", "Avg Price", "Return %", "Volatility", "Users")
	fmt.Println()
	fmt.Println(header)
	fmt.Println("  " + strings.Repeat("-", len(header)-2))

	empty := true
	for rows.Next() {
		var symbol, quote string
		var volume, avgPrice, returnPct, volatility float64
		var tradeCount, users int64
		if err := rows.Scan(&symbol, &quote, &volume, &tradeCount, &avgPrice, &returnPct, &volatility, &users); err != nil {
			fmt.Println("scan error:", err)
			return
		}
		fmt.Printf("  %-6s  %-5s  %12.4f  %8d  %14.6f  %+12.2f  %14.6f  %8d\n",
			symbol, quote, volume, tradeCount, avgPrice, returnPct, volatility, users)
		empty = false
	}
	if empty {
		fmt.Println("  (no market trades in that range)")
	}
}
