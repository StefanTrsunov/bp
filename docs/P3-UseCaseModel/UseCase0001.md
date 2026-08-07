# Use-case 0001 — Register new account

**Initiating actor:** Visitor

**Other actors:** —

A new person creates an account on EduBerza so they can later log in as a Trader. The system validates input, refuses duplicates, and stores a hashed password.

## Scenario

1. Visitor chooses "Register" from the anonymous menu.
2. System prompts for username, email, full name and password.
3. Visitor enters values.
4. System validates:
   - username, email, password are non-empty.
   - email contains `@`.
   - password is at least 6 characters.
5. System checks whether the chosen username or email already exists:

   ```sql
   SELECT EXISTS (
       SELECT 1 FROM project.users
        WHERE username = $1 OR email = $2
   );
   ```
6. If the row exists, system informs the user and the scenario ends. Otherwise it creates the account:

   ```sql
   INSERT INTO project.users (username, email, full_name, password_hash, available_balance)
   VALUES ($1, $2, $3, encode(digest($4, 'sha256'), 'hex'), 0);
   ```
7. System confirms success and returns to the anonymous menu; Visitor can then proceed to UC0002.

### Alternate flow 3a — invalid email

If step 4 fails email validation, system shows "Invalid email." and scenario returns to step 2.

### Alternate flow 5a — duplicate

If step 5 returns `true`, system shows "Username or email already taken." and scenario ends.
