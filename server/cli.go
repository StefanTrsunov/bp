package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// Session holds the currently-logged-in user, if any.
type Session struct {
	UserID   string
	Username string
}

var stdin = bufio.NewReader(os.Stdin)

func prompt(label string) string {
	fmt.Print(label)
	line, err := stdin.ReadString('\n')
	// On EOF (Ctrl-D, or the end of a piped script) ReadString keeps returning
	// an error forever. Without this the menu loop would spin printing
	// "Unknown option." indefinitely instead of ending.
	if err != nil && strings.TrimSpace(line) == "" {
		fmt.Println("\nInput closed. Goodbye.")
		os.Exit(0)
	}
	return strings.TrimSpace(line)
}

func RunCLI() {
	fmt.Println("=========================================")
	fmt.Println("  EduBerza - Crypto Exchange Simulation")
	fmt.Println("=========================================")

	var s Session
	for {
		if s.UserID == "" {
			anonymousMenu(&s)
		} else {
			authenticatedMenu(&s)
		}
	}
}

func anonymousMenu(s *Session) {
	fmt.Println()
	fmt.Println("[1] Register")
	fmt.Println("[2] Login")
	fmt.Println("[3] Browse markets")
	fmt.Println("[0] Exit")
	switch prompt("> ") {
	case "1":
		Register()
	case "2":
		Login(s)
	case "3":
		ListMarkets()
	case "0":
		fmt.Println("Goodbye.")
		os.Exit(0)
	default:
		fmt.Println("Unknown option.")
	}
}

func authenticatedMenu(s *Session) {
	fmt.Printf("\n--- Logged in as %s ---\n", s.Username)
	fmt.Println("[1] View balance")
	fmt.Println("[2] Deposit virtual funds")
	fmt.Println("[3] Browse markets")
	fmt.Println("[4] Place market BUY order")
	fmt.Println("[5] Place market SELL order")
	fmt.Println("[6] View portfolio")
	fmt.Println("[7] View transaction history")
	fmt.Println("[8] Manage watchlist")
	fmt.Println("[9] Logout")
	fmt.Println("[0] Exit")
	switch prompt("> ") {
	case "1":
		ShowBalance(s)
	case "2":
		Deposit(s)
	case "3":
		ListMarkets()
	case "4":
		PlaceOrder(s, "buy")
	case "5":
		PlaceOrder(s, "sell")
	case "6":
		ShowPortfolio(s)
	case "7":
		ShowTransactions(s)
	case "8":
		ManageWatchlist(s)
	case "9":
		s.UserID = ""
		s.Username = ""
		fmt.Println("Logged out.")
	case "0":
		fmt.Println("Goodbye.")
		os.Exit(0)
	default:
		fmt.Println("Unknown option.")
	}
}
