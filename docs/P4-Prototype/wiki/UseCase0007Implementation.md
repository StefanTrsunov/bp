= Use-case 0007 Implementation - Manage watchlist =

'''Initiating actor:''' Trader

'''Other actors:''' —

A logged-in Trader keeps a list of crypto assets they want to monitor, with the last
price of each. The first time the watchlist is opened the system creates a default
watchlist named "Favorites" for the Trader. From a sub-menu the Trader can list the
watchlist, add a crypto or remove one. The Trader never types a symbol: for adding, the
system lists, numbered, only the cryptos that are not on the watchlist yet, and for
removing, only the cryptos that are on it; the Trader picks one by its number. Adding
a crypto that is already on the list is a no-op (idempotent), and a number that is not
in the list is refused without touching the database.

Original use-case description (P3): [wiki:UseCase0007].
Implementation: `server/watchlist.go`, functions
`ManageWatchlist`, `ensureDefaultWatchlist`, `listWatchlist`, `addToWatchlist` and
`removeFromWatchlist`, with `pickNumber` from
`server/market.go` (the code is shown at the end of this page).

All statements run on the `project` schema (the connection sets
`search_path=project,public` in `server/db/db.go`). The SQL below is copied from the
Go code; only the Go source indentation is removed.

The run shown is user `alice` on the seed data, whose watchlist contains BTC, ETH and
SOL. She lists it, adds ADA, tries to remove a number that is not in the list, removes
SOL and lists the result.

== Scenario ==

 1. '''Trader''' chooses `[8] Manage watchlist` in the authenticated menu (types `8`).
 2. '''System''' makes sure the Trader has a watchlist and takes the id of the oldest one
    (`ensureDefaultWatchlist`; `$1` = the logged-in user's id):

{{{
SELECT id FROM watchlists WHERE user_id = $1 ORDER BY created_at LIMIT 1
}}}

Only if this returns no row, it creates the default watchlist and uses its id:

{{{
INSERT INTO watchlists (user_id, name) VALUES ($1, 'Favorites') RETURNING id
}}}

(alice already has the seed watchlist "Favorites", so only the `SELECT` runs.) The
watchlist id is kept in Go and used as `$1` in all statements below.

 3. '''System''' shows the sub-menu `-- Watchlist --` with `[1] List items`,
    `[2] Add crypto`, `[3] Remove crypto` and `[0] Back`.

[[Image(uc0007_1_3_menu.png)]]

=== List items ===

 4. '''Trader''' chooses `[1] List items`.
 5. '''System''' lists the cryptos on the watchlist with their last price against USD
    (`listWatchlist`; `$1` = watchlist id):

{{{
SELECT c.symbol, c.name, COALESCE(lp.price, 0)
  FROM watchlist_items wi
  JOIN crypto  c  ON c.id = wi.crypto_id
  LEFT JOIN markets       m  ON m.crypto_id = c.id AND m.quote_currency = 'USD'
  LEFT JOIN v_latest_prices lp ON lp.market_id = m.id
 WHERE wi.watchlist_id = $1
 ORDER BY c.symbol
}}}

For alice it prints `BTC Bitcoin 67140.000000`, `ETH Ethereum 3520.000000` and
`SOL Solana 166.100000` (an empty watchlist prints `(watchlist is empty)`), then
shows the sub-menu again.

[[Image(uc0007_list.png)]]

=== Add a crypto ===

 6. '''Trader''' chooses `[2] Add crypto`.
 7. '''System''' lists, numbered, the cryptos that are not on the watchlist yet
    (`addToWatchlist`; `$1` = watchlist id):

{{{
SELECT c.id, c.symbol, c.name
  FROM crypto c
 WHERE NOT EXISTS (SELECT 1 FROM watchlist_items wi
                    WHERE wi.watchlist_id = $1 AND wi.crypto_id = c.id)
 ORDER BY c.symbol
}}}

For alice it prints `1 ADA Cardano` and `2 DOGE Dogecoin` and asks
`Crypto # to add:`. Go keeps each row's crypto id in memory. (If every crypto is
already on the watchlist, it prints `Every crypto is already on your watchlist.`
instead.)

[[Image(uc0007_add_1_list.png)]]

 8. '''Trader''' picks the crypto by its number in the list: `1` (ADA).
 9. '''System''' adds the crypto of row 1 to the watchlist (`$1` = watchlist id,
    `$2` = the chosen crypto's id); thanks to the unique constraint and
    `ON CONFLICT ... DO NOTHING`, adding a crypto that is already there changes
    nothing:

{{{
INSERT INTO watchlist_items (watchlist_id, crypto_id)
 VALUES ($1, $2)
 ON CONFLICT (watchlist_id, crypto_id) DO NOTHING
}}}

It prints `Added ADA.` and shows the sub-menu again.

[[Image(uc0007_add_2_added.png)]]

=== Remove a crypto ===

 10. '''Trader''' chooses `[3] Remove crypto`.
 11. '''System''' lists, numbered, the cryptos that are on the watchlist
     (`removeFromWatchlist`; `$1` = watchlist id):

{{{
SELECT c.id, c.symbol, c.name
  FROM watchlist_items wi
  JOIN crypto c ON c.id = wi.crypto_id
 WHERE wi.watchlist_id = $1
 ORDER BY c.symbol
}}}

For alice it now prints `1 ADA Cardano`, `2 BTC Bitcoin`, `3 ETH Ethereum` and
`4 SOL Solana` and asks `Crypto # to remove:`. Go keeps each row's crypto id in
memory. (If the watchlist is empty, it prints `Your watchlist is empty.` instead.)

[[Image(uc0007_remove_1_list.png)]]

 12. '''Trader''' picks the crypto by its number in the list: `4` (SOL).
 13. '''System''' removes the crypto of row 4 from the watchlist (`$1` = watchlist id,
     `$2` = the chosen crypto's id):

{{{
DELETE FROM watchlist_items WHERE watchlist_id = $1 AND crypto_id = $2
}}}

It prints `Removed SOL.` and shows the sub-menu again.

[[Image(uc0007_remove_2_removed.png)]]

==== Alternate flow 12a — number not in the list ====

Before removing SOL, alice first chose `[3] Remove crypto` and, at step 12, entered `5`
while only numbers 1–4 were listed. `pickNumber` prints
`Invalid choice, enter a number from 1 to 4.`, the `DELETE` is not run and the sub-menu
is shown again; she then chose `[3]` once more, which returned the scenario to step 11.
The same check applies to the number entered at step 8.

[[Image(uc0007_remove_invalid.png)]]

=== Verification — list after the changes ===

Choosing `[1] List items` again runs the query from step 5, which now returns
`ADA Cardano 0.453750`, `BTC Bitcoin 67140.000000` and `ETH Ethereum 3520.000000`:
ADA was added and SOL removed. `[0] Back` returns to the authenticated menu.

[[Image(uc0007_list_after.png)]]

== Source code ==

`server/watchlist.go` — `ManageWatchlist`, `ensureDefaultWatchlist`, `listWatchlist`, `addToWatchlist` and `removeFromWatchlist`:

{{{
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
}}}

`server/market.go` — `pickNumber`:

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
}}}
