package main

import (
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/lib/pq"

	"bp_project/server/db"
)

// PlaceOrder - UC0004 (buy) / UC0005 (sell)
// Market or limit order. All the database work — checking free cash/crypto,
// reserving it, recording the order, matching it against the order book and
// filling the rest from the simulated market — is done by the P7 stored
// function project.place_order in one call, so it is one atomic statement
// and the P7 triggers keep orders, trades, holdings and balances consistent.
func PlaceOrder(s *Session, side string) {
	if side != "buy" && side != "sell" {
		fmt.Println("Invalid side.")
		return
	}
	fmt.Printf("\n-- Place %s order --\n", side)

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
	printBookSide(m, side)

	fmt.Println("[1] Market order (fills now at the best available price)")
	fmt.Println("[2] Limit order (fills only at your price or better, otherwise waits in the order book)")
	orderType := map[string]string{"1": "market", "2": "limit"}[prompt("> ")]
	if orderType == "" {
		fmt.Println("Unknown option.")
		return
	}

	qty, err := strconv.ParseFloat(prompt("Quantity: "), 64)
	if err != nil || qty <= 0 {
		fmt.Println("Invalid quantity.")
		return
	}
	var limit optFloat
	if orderType == "limit" {
		p, err := strconv.ParseFloat(prompt("Limit price: "), 64)
		if err != nil || p <= 0 {
			fmt.Println("Invalid price.")
			return
		}
		limit = optFloat{p, true}
	}

	var orderID string
	err = db.DB.QueryRow(
		`SELECT place_order($1, $2, $3, $4, $5, $6)`,
		s.UserID, m.ID, side, orderType, qty, limit.value(),
	).Scan(&orderID)
	if err != nil {
		fmt.Println(dbMessage(err))
		return
	}

	var status string
	var filled, remaining float64
	var avg *float64
	if err := db.DB.QueryRow(
		`SELECT status, filled_quantity, remaining, avg_fill_price
		   FROM v_order_history WHERE order_id = $1`, orderID,
	).Scan(&status, &filled, &remaining, &avg); err != nil {
		fmt.Println("Error:", err)
		return
	}
	switch status {
	case "executed":
		fmt.Printf("Order executed: %s %.4f %s, average price %.6f\n", side, filled, m.Symbol, *avg)
	case "partially_filled":
		fmt.Printf("Order partially filled: %.4f %s at average %.6f, %.4f waiting in the order book\n",
			filled, m.Symbol, *avg, remaining)
	default:
		fmt.Printf("Order placed in the order book: %s %.4f %s at %.6f\n", side, remaining, m.Symbol, limit.v)
	}
}

// optFloat is an optional float parameter (NULL when not set).
type optFloat struct {
	v  float64
	ok bool
}

func (n optFloat) value() any {
	if !n.ok {
		return nil
	}
	return n.v
}

// dbMessage shows a rule the database refused (P7 raises check_violation
// with a readable message) without the driver's prefix.
func dbMessage(err error) string {
	var pqErr *pq.Error
	if errors.As(err, &pqErr) && pqErr.Code.Class() == "23" {
		return "Rejected: " + pqErr.Message
	}
	return "Error: " + err.Error()
}

// printBookSide shows the best resting orders on the side this order would
// trade against (asks for a buy, bids for a sell).
func printBookSide(m *Market, side string) {
	other, order := "sell", "price ASC"
	if side == "sell" {
		other, order = "buy", "price DESC"
	}
	rows, err := db.DB.Query(
		`SELECT price, quantity, orders FROM v_order_book
		  WHERE market_id = $1 AND side = $2 ORDER BY `+order+` LIMIT 5`, m.ID, other)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	defer rows.Close()
	label := map[string]string{"sell": "asks", "buy": "bids"}[other]
	first := true
	for rows.Next() {
		var price, qty float64
		var n int
		if err := rows.Scan(&price, &qty, &n); err != nil {
			fmt.Println("scan error:", err)
			return
		}
		if first {
			fmt.Printf("Order book %s (other users' limit orders):\n", label)
			first = false
		}
		fmt.Printf("  %14.6f  %12.4f  (%d orders)\n", price, qty, n)
	}
	if first {
		fmt.Printf("Order book has no %s - a market order fills from the simulated market.\n", label)
	}
}

// ShowOrderBook - P7 view v_order_book for one market.
func ShowOrderBook() {
	m, err := ChooseMarket()
	if err != nil {
		fmt.Println(err)
		return
	}
	rows, err := db.DB.Query(
		`SELECT side, price, quantity, orders FROM v_order_book
		  WHERE market_id = $1
		  ORDER BY side DESC, price DESC`, m.ID)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}
	defer rows.Close()
	fmt.Printf("\n  Order book %s/%s\n", m.Symbol, m.Quote)
	fmt.Printf("  %-5s  %14s  %12s  %6s\n", "Side", "Price", "Quantity", "Orders")
	fmt.Println("  " + strings.Repeat("-", 44))
	empty := true
	for rows.Next() {
		var side string
		var price, qty float64
		var n int
		if err := rows.Scan(&side, &price, &qty, &n); err != nil {
			fmt.Println("scan error:", err)
			return
		}
		fmt.Printf("  %-5s  %14.6f  %12.4f  %6d\n", map[string]string{"sell": "ask", "buy": "bid"}[side], price, qty, n)
		empty = false
	}
	if empty {
		fmt.Println("  (no resting limit orders)")
	}
}

// activeOrder is one row of the user's open orders list.
type activeOrder struct {
	id, symbol, side, typ, status string
	qty, filled, remaining, price float64
}

// listMyOrders prints the user's active orders numbered 1..n (P7 view
// v_active_orders) and returns them, so the user can pick one by number.
func listMyOrders(s *Session) []activeOrder {
	rows, err := db.DB.Query(
		`SELECT order_id, symbol, side, type, status, quantity, filled_quantity, remaining, price
		   FROM v_active_orders WHERE user_id = $1 ORDER BY placed_at`, s.UserID)
	if err != nil {
		fmt.Println("Error:", err)
		return nil
	}
	defer rows.Close()
	var list []activeOrder
	for rows.Next() {
		var o activeOrder
		if err := rows.Scan(&o.id, &o.symbol, &o.side, &o.typ, &o.status,
			&o.qty, &o.filled, &o.remaining, &o.price); err != nil {
			fmt.Println("scan error:", err)
			return nil
		}
		list = append(list, o)
	}
	fmt.Println()
	if len(list) == 0 {
		fmt.Println("  (no open orders)")
		return nil
	}
	fmt.Printf("  %-3s  %-6s  %-4s  %-6s  %-16s  %10s  %10s  %14s\n",
		"#", "Symbol", "Side", "Type", "Status", "Filled", "Remaining", "Price")
	fmt.Println("  " + strings.Repeat("-", 84))
	for i, o := range list {
		fmt.Printf("  %-3d  %-6s  %-4s  %-6s  %-16s  %10.4f  %10.4f  %14.6f\n",
			i+1, o.symbol, o.side, o.typ, o.status, o.filled, o.remaining, o.price)
	}
	return list
}

// ShowMyOrders - P7 view v_active_orders.
func ShowMyOrders(s *Session) {
	listMyOrders(s)
}

// CancelOrder - P7 stored function project.cancel_order, which releases
// the reserved cash or crypto of what is still unfilled.
func CancelOrder(s *Session) {
	list := listMyOrders(s)
	if len(list) == 0 {
		return
	}
	n, err := strconv.Atoi(prompt("Order # to cancel (0 = back): "))
	if err != nil || n < 0 || n > len(list) {
		fmt.Println("Invalid choice.")
		return
	}
	if n == 0 {
		return
	}
	if _, err := db.DB.Exec(`SELECT cancel_order($1, $2)`, list[n-1].id, s.UserID); err != nil {
		fmt.Println(dbMessage(err))
		return
	}
	fmt.Println("Order cancelled; its reservation was released.")
}
