= Use-case 0001 Implementation - Register new account =

'''Initiating actor:''' Visitor

'''Other actors:''' —

A new person creates an account on !EduBerza so that they can later log in as a
Trader ([wiki:UseCase0002Implementation UseCase0002]). The Visitor enters a
username, an e-mail address, a full name and a password. The system validates the
input (required fields, an `@` in the e-mail, a password of at least 6 characters),
refuses a username or e-mail that is already registered, and stores only a SHA-256
hash of the password, never the password itself. A new account starts with a cash
balance of 0 USD; money is added later with a deposit
([wiki:UseCase0003Implementation UseCase0003]).

Original use-case description (P3): [wiki:UseCase0001].
Implementation: `server/auth.go`, function `Register` (the password hash is computed
by `hashPassword` in the same file; the code is shown at the end of this page).

== Scenario ==

 1. '''Visitor''' chooses `[1] Register` in the anonymous menu (types `1`).
 2. '''System''' prints `-- Register --` and asks, one prompt after another, for
    `Username:`, `Email:`, `Full name:` and `Password (min 6 chars):`.

The screenshot shows steps 1–2: option `1` is chosen and the first prompt
(`Username:`) is waiting for input.

[[Image(uc0001_1_register.png)]]

 3. '''Visitor''' enters the values: `marko`, `marko@example.com`, `Marko Markovski`,
    `secret1`.
 4. '''System''' validates the input in Go, without accessing the database:
   * username, e-mail and password must be non-empty, otherwise it prints
     `Username, email and password are required.` and the scenario ends;
   * the e-mail must contain `@` (see alternate flow 3a);
   * the password must be at least 6 characters long, otherwise it prints
     `Password must be at least 6 characters.` and the scenario ends.
 5. '''System''' checks whether the username or the e-mail already exists
    (`$1` = username, `$2` = e-mail):

{{{
SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 OR email = $2)
}}}

If the result is `true`, alternate flow 5a applies.

 6. '''System''' creates the account (`$1` = username, `$2` = e-mail, `$3` = full name,
    `$4` = password hash). The hash is computed in Go by `hashPassword` as the
    hex-encoded SHA-256 of the password — the same value that P3's
    `encode(digest($4, 'sha256'), 'hex')` would produce in SQL. Hashing on the Go side
    keeps it identical to the check done at login (SQL as in the code, only the Go
    source indentation removed):

{{{
INSERT INTO users (username, email, full_name, password_hash, available_balance)
VALUES ($1, $2, $3, $4, 0)
}}}

 7. '''System''' prints `Account created. You can now log in.` and returns to the
    anonymous menu; the Visitor can continue with
    [wiki:UseCase0002Implementation UseCase0002].

The screenshot shows steps 3–7 of the successful attempt (bottom half): the
entered values, the confirmation and the anonymous menu again. The top half is the
earlier rejected attempt from alternate flow 3a.

[[Image(uc0001_3_7_created.png)]]

All statements are run on the `project` schema: the connection sets
`search_path=project,public` (`server/db/db.go`), so `users` means `project.users`.

=== Alternate flow 3a — invalid e-mail ===

In step 3 the Visitor entered `marko.example.com` (no `@`). The check in step 4
fails, the system prints `Invalid email.` and no SQL statement is executed. In the
prototype the system then shows the anonymous menu again and the Visitor chooses
`[1] Register` once more, which returns the scenario to step 2.

[[Image(uc0001_3a_invalid_email.png)]]

=== Alternate flow 5a — duplicate username or e-mail ===

After `marko` has been created, the Visitor tries to register again with username
`marko`, e-mail `other@example.com`, full name `Marko Two`, password `secret2`. The
query from step 5 (`$1` = `marko`, `$2` = `other@example.com`) returns `true`
because the username is taken, so the system prints
`Username or email already taken.`, does not run the `INSERT`, and the scenario
ends in the anonymous menu.

[[Image(uc0001_5a_duplicate.png)]]

== How to reproduce ==

{{{
./eduberza -init      # optional: reset to a known state
./eduberza
# [1] Register: marko / marko.example.com / Marko Markovski / secret1  -> Invalid email.
# [1] Register: marko / marko@example.com / Marko Markovski / secret1  -> Account created.
# [1] Register: marko / other@example.com / Marko Two / secret2        -> Username or email already taken.
}}}

All three screenshots come from one real run of exactly these inputs.

== Source code ==

`server/auth.go` — `hashPassword` and `Register`:

{{{
func hashPassword(pw string) string {
	sum := sha256.Sum256([]byte(pw))
	return hex.EncodeToString(sum[:])
}

// Register - UC0001
func Register() {
	fmt.Println("\n-- Register --")
	username := prompt("Username: ")
	email := prompt("Email: ")
	fullName := prompt("Full name: ")
	pw := prompt("Password (min 6 chars): ")

	if username == "" || email == "" || pw == "" {
		fmt.Println("Username, email and password are required.")
		return
	}
	if !strings.Contains(email, "@") {
		fmt.Println("Invalid email.")
		return
	}
	if len(pw) < 6 {
		fmt.Println("Password must be at least 6 characters.")
		return
	}

	var exists bool
	err := db.DB.QueryRow(
		`SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 OR email = $2)`,
		username, email,
	).Scan(&exists)
	if err != nil {
		fmt.Println("Database error:", err)
		return
	}
	if exists {
		fmt.Println("Username or email already taken.")
		return
	}

	_, err = db.DB.Exec(
		`INSERT INTO users (username, email, full_name, password_hash, available_balance)
		 VALUES ($1, $2, $3, $4, 0)`,
		username, email, fullName, hashPassword(pw),
	)
	if err != nil {
		fmt.Println("Failed to register:", err)
		return
	}
	fmt.Println("Account created. You can now log in.")
}
}}}
