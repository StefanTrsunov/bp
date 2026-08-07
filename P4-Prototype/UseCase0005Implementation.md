# Use-case 0005 Implementation — Sell

**Initiating actor:** Trader. **Source file:** `server/trade.go`, function `PlaceOrder(s, "sell")`.

## Scenario (implemented)

1. **User** chooses `[5] Place market SELL order`.
2. **System** lists markets (same as UC0004 step 2).
3. **User** enters market symbol, e.g. `ETH`, then quantity `0.5`.
4. **System** opens a transaction and runs:

   ```sql
   BEGIN;

   INSERT INTO orders
       (user_id, market_id, side, type, status, quantity, price, executed_at)
   VALUES
       ($1, $2, 'sell', 'market', 'executed', $3, $4, now())
   RETURNING id;

   SELECT quantity, avg_price FROM holdings
    WHERE user_id = $1 AND crypto_id = $c FOR UPDATE;
   -- abort if missing or insufficient

   UPDATE holdings
      SET quantity = quantity - $qty, updated_at = now()
    WHERE user_id = $1 AND crypto_id = $c;

   UPDATE users
      SET available_balance = available_balance + $notional,
          invested_balance  = GREATEST(invested_balance - ($avg * $qty), 0),
          updated_at        = now()
    WHERE id = $1;

   INSERT INTO transactions
       (user_id, type, amount, currency, related_order, description)
   VALUES
       ($1, 'sell', $notional, 'USD', $orderId, 'Market sell ...');

   INSERT INTO market_trades
       (market_id, executed_at, price, quantity, side, source)
   VALUES
       ($2, now(), $price, $qty, 'sell', 'user');

   COMMIT;
   ```

   ![Selling 0.5 ETH at the current market price](screenshots/uc0005_sell.png)

5. **System** prints: `Order executed: sell 0.5000 ETH @ 3520.000000 (notional 1760.0000 USD)`.

## Failure path — insufficient holding

If the holding does not exist or `quantity < requested`, the `defer tx.Rollback()` in `server/trade.go` reverts every statement above and the user sees:

```
Insufficient holding: trying to sell X, hold Y
```
