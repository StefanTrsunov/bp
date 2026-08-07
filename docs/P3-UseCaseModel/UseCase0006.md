# Use-case 0006 — View portfolio and transaction history

**Initiating actor:** Trader

**Other actors:** —

A Trader inspects their current holdings, unrealised P/L, cash balance and recent ledger.

## Scenario

### Portfolio

1. Trader chooses "View portfolio".
2. System queries the `v_portfolio` view:

   ```sql
   SELECT symbol,
          quantity,
          COALESCE(avg_price,      0),
          COALESCE(current_price,  0),
          COALESCE(market_value,   0),
          COALESCE(unrealized_pnl, 0)
     FROM project.v_portfolio
    WHERE user_id = $1
      AND quantity > 0
    ORDER BY symbol;
   ```
3. System displays the rows and a computed summary:

   ```sql
   SELECT available_balance, invested_balance
     FROM project.users
    WHERE id = $1;
   ```

### Transaction history

1. Trader chooses "View transaction history".
2. System queries the last 20 ledger entries:

   ```sql
   SELECT created_at, type, amount, currency, COALESCE(description, '')
     FROM project.transactions
    WHERE user_id = $1
    ORDER BY created_at DESC
    LIMIT 20;
   ```

### Reference — how `v_portfolio` is defined

```sql
CREATE OR REPLACE VIEW project.v_portfolio AS
SELECT h.user_id,
       c.symbol,
       h.quantity,
       h.avg_price,
       lp.price                                AS current_price,
       (h.quantity * lp.price)                 AS market_value,
       (h.quantity * (lp.price - h.avg_price)) AS unrealized_pnl
  FROM project.holdings h
  JOIN project.crypto   c ON c.id = h.crypto_id
  LEFT JOIN project.markets m
         ON m.crypto_id = c.id AND m.quote_currency = 'USD'
  LEFT JOIN project.v_latest_prices lp
         ON lp.market_id = m.id;
```
