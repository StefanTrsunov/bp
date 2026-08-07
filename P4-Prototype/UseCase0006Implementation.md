# Use-case 0006 Implementation — Portfolio & transactions

**Initiating actor:** Trader. **Source files:** `server/portfolio.go` (`ShowPortfolio`), `server/account.go` (`ShowTransactions`, `ShowBalance`).

## Scenario (implemented)

### Portfolio

1. **User** chooses `[6] View portfolio`.
2. **System** runs:

   ```sql
   SELECT symbol, quantity,
          COALESCE(avg_price,      0),
          COALESCE(current_price,  0),
          COALESCE(market_value,   0),
          COALESCE(unrealized_pnl, 0)
     FROM v_portfolio
    WHERE user_id = $1 AND quantity > 0
    ORDER BY symbol;
   ```
3. **System** renders a table with a totals row, then prints the cash summary:

   ```sql
   SELECT available_balance, invested_balance FROM users WHERE id = $1;
   ```

   ![screenshot: portfolio view](screenshots/uc0006_portfolio.png)

### Verified run

With the seed data (`data_load.sql`), immediately after login, alice's portfolio prints:

```
  Symbol        Quantity         Avg buy         Current           Value  Unrealised P/L
  ------------------------------------------------------------------------------------
  ETH             0.5000     3500.000000     3520.000000       1760.0000        +10.0000
  ------------------------------------------------------------------------------------
  TOTAL                                                        1760.0000        +10.0000

  Cash available : 8250.0000 USD
  Portfolio value: 1760.0000 USD
  Net worth      : 10010.0000 USD
```

### Transaction history

1. **User** chooses `[7] View transaction history`.
2. **System** runs:

   ```sql
   SELECT created_at, type, amount, currency, COALESCE(description, '')
     FROM transactions
    WHERE user_id = $1
    ORDER BY created_at DESC
    LIMIT 20;
   ```

   ![screenshot: transaction history](screenshots/uc0006_history.png)
