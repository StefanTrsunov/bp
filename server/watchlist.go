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

func addToWatchlist(wlID string) {
	sym := prompt("Crypto symbol to add: ")
	var cryptoID string
	err := db.DB.QueryRow(
		`SELECT id FROM crypto WHERE upper(symbol) = upper($1)`, sym,
	).Scan(&cryptoID)
	if err == sql.ErrNoRows {
		fmt.Println("Unknown crypto symbol.")
		return
	}
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	_, err = db.DB.Exec(
		`INSERT INTO watchlist_items (watchlist_id, crypto_id)
		 VALUES ($1, $2)
		 ON CONFLICT (watchlist_id, crypto_id) DO NOTHING`,
		wlID, cryptoID,
	)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	fmt.Println("Added.")
}

func removeFromWatchlist(wlID string) {
	sym := prompt("Crypto symbol to remove: ")
	res, err := db.DB.Exec(`
		DELETE FROM watchlist_items
		 WHERE watchlist_id = $1
		   AND crypto_id = (SELECT id FROM crypto WHERE upper(symbol) = upper($2))`,
		wlID, sym)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		fmt.Println("Not in watchlist.")
		return
	}
	fmt.Println("Removed.")
}
