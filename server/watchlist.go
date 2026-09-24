package main

import (
	"database/sql"
	"fmt"

	"bp_project/server/db"
)

// ManageWatchlist - UC0007
// Ensures the user has a default watchlist, then allows listing, adding,
// removing entries.
func ManageWatchlist(s *Session) {
	wlID, err := ensureDefaultWatchlist(s.UserID)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	for {
		fmt.Println("\n-- Watchlist --")
		fmt.Println("[1] List items")
		fmt.Println("[2] Add crypto")
		fmt.Println("[3] Remove crypto")
		fmt.Println("[0] Back")
		switch prompt("> ") {
		case "1":
			listWatchlist(wlID)
		case "2":
			addToWatchlist(wlID)
		case "3":
			removeFromWatchlist(wlID)
		case "0":
			return
		default:
			fmt.Println("Unknown option.")
		}
	}
}

func ensureDefaultWatchlist(userID string) (string, error) {
	var id string
	err := db.DB.QueryRow(
		`SELECT id FROM watchlists WHERE user_id = $1 ORDER BY created_at LIMIT 1`,
		userID,
	).Scan(&id)
	if err == sql.ErrNoRows {
		err = db.DB.QueryRow(
			`INSERT INTO watchlists (user_id, name) VALUES ($1, 'Favorites') RETURNING id`,
			userID,
		).Scan(&id)
		return id, err
	}
	return id, err
}

func listWatchlist(wlID string) {
	rows, err := db.DB.Query(`
		SELECT c.symbol, c.name, COALESCE(lp.price, 0)
		  FROM watchlist_items wi
		  JOIN crypto  c  ON c.id = wi.crypto_id
		  LEFT JOIN markets       m  ON m.crypto_id = c.id AND m.quote_currency = 'USD'
		  LEFT JOIN v_latest_prices lp ON lp.market_id = m.id
		 WHERE wi.watchlist_id = $1
		 ORDER BY c.symbol`, wlID)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	defer rows.Close()

	fmt.Println()
	fmt.Printf("  %-8s  %-20s  %15s\n", "Symbol", "Name", "Last price")
	fmt.Println("  --------------------------------------------------")
	empty := true
	for rows.Next() {
		var sym, name string
		var price float64
		if err := rows.Scan(&sym, &name, &price); err != nil {
			fmt.Println("scan error:", err)
			return
		}
		fmt.Printf("  %-8s  %-20s  %15.6f\n", sym, name, price)
		empty = false
	}
	if empty {
		fmt.Println("  (watchlist is empty)")
	}
}

// addToWatchlist lists the cryptos that are not on the watchlist yet,
// numbered, and adds the one the user picks.
func addToWatchlist(wlID string) {
	rows, err := db.DB.Query(`
		SELECT c.id, c.symbol, c.name
		  FROM crypto c
		 WHERE NOT EXISTS (SELECT 1 FROM watchlist_items wi
		                    WHERE wi.watchlist_id = $1 AND wi.crypto_id = c.id)
		 ORDER BY c.symbol`, wlID)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	type option struct{ id, symbol, name string }
	var list []option
	for rows.Next() {
		var o option
		if err := rows.Scan(&o.id, &o.symbol, &o.name); err != nil {
			rows.Close()
			fmt.Println("scan error:", err)
			return
		}
		list = append(list, o)
	}
	rows.Close()
	if len(list) == 0 {
		fmt.Println("Every crypto is already on your watchlist.")
		return
	}
	fmt.Println()
	fmt.Printf("  %-4s  %-8s  %s\n", "#", "Symbol", "Name")
	fmt.Println("  ------------------------------")
	for i, o := range list {
		fmt.Printf("  %-4d  %-8s  %s\n", i+1, o.symbol, o.name)
	}
	k, err := pickNumber("Crypto # to add: ", len(list))
	if err != nil {
		fmt.Println(err)
		return
	}
	_, err = db.DB.Exec(
		`INSERT INTO watchlist_items (watchlist_id, crypto_id)
		 VALUES ($1, $2)
		 ON CONFLICT (watchlist_id, crypto_id) DO NOTHING`,
		wlID, list[k].id,
	)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	fmt.Printf("Added %s.\n", list[k].symbol)
}

// removeFromWatchlist lists the watchlist's cryptos, numbered, and removes
// the one the user picks.
func removeFromWatchlist(wlID string) {
	rows, err := db.DB.Query(`
		SELECT c.id, c.symbol, c.name
		  FROM watchlist_items wi
		  JOIN crypto c ON c.id = wi.crypto_id
		 WHERE wi.watchlist_id = $1
		 ORDER BY c.symbol`, wlID)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	type option struct{ id, symbol, name string }
	var list []option
	for rows.Next() {
		var o option
		if err := rows.Scan(&o.id, &o.symbol, &o.name); err != nil {
			rows.Close()
			fmt.Println("scan error:", err)
			return
		}
		list = append(list, o)
	}
	rows.Close()
	if len(list) == 0 {
		fmt.Println("Your watchlist is empty.")
		return
	}
	fmt.Println()
	fmt.Printf("  %-4s  %-8s  %s\n", "#", "Symbol", "Name")
	fmt.Println("  ------------------------------")
	for i, o := range list {
		fmt.Printf("  %-4d  %-8s  %s\n", i+1, o.symbol, o.name)
	}
	k, err := pickNumber("Crypto # to remove: ", len(list))
	if err != nil {
		fmt.Println(err)
		return
	}
	if _, err := db.DB.Exec(
		`DELETE FROM watchlist_items WHERE watchlist_id = $1 AND crypto_id = $2`,
		wlID, list[k].id,
	); err != nil {
		fmt.Println("Error:", err)
		return
	}
	fmt.Printf("Removed %s.\n", list[k].symbol)
}
