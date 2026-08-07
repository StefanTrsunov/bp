package main

import (
	"fmt"
	"strconv"
	"strings"

	"bp_project/server/db"
)

// ShowBalance prints the logged-in user's balances.
func ShowBalance(s *Session) {
	var avail, invested float64
	err := db.DB.QueryRow(
		`SELECT available_balance, invested_balance FROM users WHERE id = $1`,
		s.UserID,
	).Scan(&avail, &invested)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	fmt.Printf("\n  Available: %.4f USD\n", avail)
	fmt.Printf("  Invested : %.4f USD\n", invested)
	fmt.Printf("  Total    : %.4f USD\n", avail+invested)
}

// Deposit - UC0003
// Transactional: updates users.available_balance and inserts a ledger row.
func Deposit(s *Session) {
	fmt.Println("\n-- Deposit virtual funds --")
	amtStr := prompt("Amount (USD): ")
	amt, err := strconv.ParseFloat(amtStr, 64)
	if err != nil || amt <= 0 {
		fmt.Println("Invalid amount.")
		return
	}

	tx, err := db.DB.Begin()
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	defer tx.Rollback()

	if _, err := tx.Exec(
		`UPDATE users
		    SET available_balance = available_balance + $1,
		        updated_at        = now()
		  WHERE id = $2`,
		amt, s.UserID,
	); err != nil {
		fmt.Println("Error:", err)
		return
	}
	if _, err := tx.Exec(
		`INSERT INTO transactions (user_id, type, amount, currency, description)
		 VALUES ($1, 'deposit', $2, 'USD', 'Virtual deposit')`,
		s.UserID, amt,
	); err != nil {
		fmt.Println("Error:", err)
		return
	}
	if err := tx.Commit(); err != nil {
		fmt.Println("Error:", err)
		return
	}
	fmt.Printf("Deposited %.4f USD.\n", amt)
}

// ShowTransactions lists the last 20 ledger entries for the user.
func ShowTransactions(s *Session) {
	rows, err := db.DB.Query(
		`SELECT created_at, type, amount, currency, COALESCE(description, '')
		   FROM transactions
		  WHERE user_id = $1
		  ORDER BY created_at DESC
		  LIMIT 20`,
		s.UserID,
	)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	defer rows.Close()

	fmt.Println()
	fmt.Printf("  %-20s  %-8s  %12s  %-3s  %s\n", "When", "Type", "Amount", "Cur", "Description")
	fmt.Println("  " + strings.Repeat("-", 70))
	for rows.Next() {
		var when, typ, cur, desc string
		var amt float64
		if err := rows.Scan(&when, &typ, &amt, &cur, &desc); err != nil {
			fmt.Println("scan error:", err)
			return
		}
		fmt.Printf("  %-20s  %-8s  %12.4f  %-3s  %s\n", when[:19], typ, amt, cur, desc)
	}
}
