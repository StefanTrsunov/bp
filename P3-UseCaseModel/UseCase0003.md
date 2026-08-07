# Use-case 0003 — Deposit virtual funds

**Initiating actor:** Trader

**Other actors:** —

A logged-in Trader tops up their virtual cash balance. This is a simulation-only operation; no real money changes hands. The operation writes to two tables — the user row and the ledger — inside a single transaction.

## Scenario

1. Trader chooses "Deposit virtual funds" from the authenticated menu.
2. System prompts for an amount in USD.
3. Trader enters an amount.
4. System validates: amount must parse as a positive number.
5. System opens a transaction and increments the balance:

   ```sql
   BEGIN;

   UPDATE project.users
      SET available_balance = available_balance + $1,
          updated_at        = now()
    WHERE id = $2;

   INSERT INTO project.transactions (user_id, type, amount, currency, description)
   VALUES ($2, 'deposit', $1, 'USD', 'Virtual deposit');

   COMMIT;
   ```
6. System confirms "Deposited X USD." and returns to the authenticated menu.

### Alternate flow 4a — invalid input

If the amount is non-positive or non-numeric, system responds "Invalid amount." and scenario returns to step 2.

### Verification query

To see the balance after the deposit, the Trader can trigger UC0006, or directly:

```sql
SELECT available_balance, invested_balance
  FROM project.users
 WHERE id = $1;
```
