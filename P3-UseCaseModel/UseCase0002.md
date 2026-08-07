# Use-case 0002 — Log in

**Initiating actor:** Visitor

**Other actors:** —

A registered user authenticates so the system can treat subsequent actions as a Trader.

## Scenario

1. Visitor chooses "Login" from the anonymous menu.
2. System prompts for username and password.
3. Visitor enters values.
4. System looks up the user:

   ```sql
   SELECT id, password_hash
     FROM project.users
    WHERE username = $1;
   ```
5. If no row is returned, system responds "Invalid credentials." and scenario ends.
6. If a row is returned, system compares the stored hash against sha256 of the entered password. On mismatch it responds "Invalid credentials." and ends.
7. On match, system records the returned `id` and username in the session and displays the authenticated menu.

### Alternate flow 4a — authenticated lookup with live balance

The system may combine identity lookup with live balance in a single query, for use cases that need both:

```sql
SELECT id, available_balance, invested_balance
  FROM project.users
 WHERE username = $1
   AND password_hash = encode(digest($2, 'sha256'), 'hex');
```
