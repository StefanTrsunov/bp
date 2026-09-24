= Use-case 0003 Implementation - Deposit virtual funds =

'''Initiating actor:''' Trader

'''Other actors:''' —

A logged-in Trader tops up their virtual cash balance in USD. This is a
simulation-only operation: no real money changes hands, the amount is simply added to
the Trader's `available_balance`. Every deposit is also recorded in the ledger
(`transactions`) so that it appears in the transaction history
([wiki:UseCase0006Implementation UseCase0006]). The operation writes to two tables —
the user row and the ledger — inside a single database transaction, so either both
changes are stored or neither is. Non-numeric, zero or negative amounts are rejected
before the database is touched.

Original use-case description (P3): [wiki:UseCase0003].
Implementation: `server/account.go`, function `Deposit`; the verification uses
`ShowBalance` from the same file (the code is shown at the end of this page).

Precondition: the Trader is logged in ([wiki:UseCase0002Implementation UseCase0002]);
in the run below as `alice`, who starts from the seed state (available 8250.00 USD,
invested 1750.00 USD).

== Scenario ==

 1. '''Trader''' chooses `[2] Deposit virtual funds` in the authenticated menu
    (types `2`).
 2. '''System''' prints `-- Deposit virtual funds --` and asks `Amount (USD):`.

The screenshot shows steps 1–2: the login as alice, the authenticated menu, the
choice `2` and the amount prompt waiting for input.

[[Image(uc0003_1_2_deposit.png)]]

 3. '''Trader''' enters an amount: `500`.
 4. '''System''' validates the input in Go, without accessing the database: the text
    must parse as a number (`strconv.ParseFloat`) and be greater than 0 (see
    alternate flow 4a).
 5. '''System''' opens one database transaction (`db.DB.Begin()`), increments the
    balance, writes the ledger row and commits. Both statements run in this single
    transaction; if either fails, the deferred `tx.Rollback()` undoes everything.
    `BEGIN` and `COMMIT` are issued by Go's `Begin()` / `Commit()`; the two
    statements are sent exactly as in the code:

{{{
BEGIN;

UPDATE users
    SET available_balance = available_balance + $1,
        updated_at        = now()
  WHERE id = $2;

INSERT INTO transactions (user_id, type, amount, currency, description)
VALUES ($1, 'deposit', $2, 'USD', 'Virtual deposit');

COMMIT;
}}}

Parameters: placeholders are numbered per statement. In the `UPDATE`, `$1` is the
amount (`500`) and `$2` the user id (`amt, s.UserID`); in the `INSERT` it is the
other way round, `$1` is the user id and `$2` the amount (`s.UserID, amt`),
matching the column order.

 6. '''System''' confirms `Deposited 500.0000 USD.` and returns to the authenticated
    menu.

The screenshot shows steps 3–6: the entered amount `500`, the confirmation and the
authenticated menu again.

[[Image(uc0003_3_6_deposited.png)]]

The statements run on the `project` schema (the connection sets
`search_path=project,public`), so `users` and `transactions` mean `project.users`
and `project.transactions`.

=== Alternate flow 4a — invalid amount ===

If the amount is not a number, or is zero or negative, the system prints
`Invalid amount.`; no transaction is started and nothing is written. In the run the
Trader first entered `-50`. In the prototype the system then shows the
authenticated menu again and the Trader chooses `[2] Deposit virtual funds` once
more, which returns the scenario to step 2.

[[Image(uc0003_4a_invalid.png)]]

== Verification ==

Right after the deposit the Trader chooses `[1] View balance` (function
`ShowBalance`), which runs (`$1` = user id):

{{{
SELECT available_balance, invested_balance FROM users WHERE id = $1
}}}

It prints `Available: 8750.0000 USD`, `Invested : 1750.0000 USD`,
`Total    : 10500.0000 USD`. The available balance grew from the seed value 8250.00
by exactly the 500.00 deposited (the rejected `-50` changed nothing), and
`invested_balance` is untouched.

[[Image(uc0003_verify_balance.png)]]

== How to reproduce ==

{{{
./eduberza -init
./eduberza
# [2] Login: alice / test123
# [2] Deposit virtual funds: -50   -> Invalid amount.
# [2] Deposit virtual funds: 500   -> Deposited 500.0000 USD.
# [1] View balance                 -> Available: 8750.0000 USD
}}}

All four screenshots come from one real run of exactly these inputs.

== Source code ==

`server/account.go` — `Deposit`, and `ShowBalance` used for the verification:

{{{
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
}}}
