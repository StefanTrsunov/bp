# Use-case 0002 Implementation - Log in

**Initiating actor:** Visitor

**Other actors:** —

A registered user authenticates with a username and password so that the system
treats all following actions as actions of that Trader. The system looks the user up
by username and compares the stored password hash with the SHA-256 hash of the
entered password. An unknown username and a wrong password give the same answer,
`Invalid credentials.`, so the system does not reveal which usernames exist. After a
successful login the user's id and username are kept in the in-process session and
the authenticated (Trader) menu is shown, from which all other Trader use-cases
start.

Original use-case description (P3): [UseCase0002](../P3-UseCaseModel/UseCase0002.md).
Implementation: [`server/auth.go`](../../server/auth.go), functions `Login` and
`authenticate` (password hash by `hashPassword`).

## Scenario

1. **Visitor** chooses `[2] Login` in the anonymous menu (types `2`).
2. **System** prints `-- Login --` and asks for `Username:` and then `Password:`.

   The screenshot shows steps 1–2: option `2` is chosen and the `Username:` prompt
   is waiting for input.

   ![UC0002 steps 1-2: Visitor chooses Login, system asks for credentials](screenshots/uc0002_1_login.png)

3. **Visitor** enters the username and the password. (If either is empty, the
   system prints `Username and password are required.` without accessing the
   database.)
4. **System** looks up the user (`$1` = entered username):

   ```sql
   SELECT id, password_hash FROM users WHERE username = $1
   ```

5. If no row is returned (`sql.ErrNoRows` in Go), the **System** responds
   `Invalid credentials.` and the scenario ends.
6. If a row is returned, the **System** compares the returned `password_hash` with
   `hashPassword(entered password)` (hex-encoded SHA-256, computed in Go). On a
   mismatch it responds `Invalid credentials.` and the scenario ends.

   The screenshot shows this failure path with an existing user and a wrong
   password: `alice` / `wrongpass`. The query from step 4 finds alice's row, the
   hash comparison of step 6 fails, and the system prints `Invalid credentials.` and
   returns to the anonymous menu. (An unknown username — step 5 — prints exactly the
   same message.)

   ![UC0002 steps 5-6: wrong password, Invalid credentials](screenshots/uc0002_5_6_invalid.png)

7. On a match, the **System** stores the returned `id` and the username in the
   session (`s.UserID`, `s.Username`), prints `Login successful.` and displays the
   authenticated menu headed `--- Logged in as alice ---`.

   The screenshot shows steps 3–7 of the second, successful attempt with the seed
   credentials `alice` / `test123` (the first, rejected attempt is still visible at
   the top of the window).

   ![UC0002 steps 3-7: correct credentials, authenticated menu](screenshots/uc0002_7_success.png)

The query runs on the `project` schema (the connection sets
`search_path=project,public`), so `users` means `project.users`.

### Alternate flow 4a (P3) — lookup combined with the live balance

P3 describes an optional variant that checks the password in SQL and returns the
balances in the same query. The P4 prototype does **not** use it: login always uses
the query from step 4 with the hash comparison in Go, and the balances are read
separately when the Trader asks for them (`[1] View balance`, see
[UseCase0003](UseCase0003Implementation.md)).

## Seed credentials

State after `./eduberza -init` (`server/db/data_load.sql`):

| Username  | Password  | Available balance | Invested balance | Holdings |
|-----------|-----------|------------------:|-----------------:|----------|
| `alice`   | `test123` | 8250.00 USD       | 1750.00 USD      | 0.5 ETH  |
| `bob`     | `test123` | 5000.00 USD       | 0.00 USD         | —        |
| `charlie` | `test123` | 2500.00 USD       | 0.00 USD         | —        |

## How to reproduce

```sh
./eduberza -init
./eduberza
# [2] Login: alice / wrongpass  -> Invalid credentials.
# [2] Login: alice / test123    -> Login successful.  (authenticated menu)
```

The screenshots come from one real run of exactly these inputs.
