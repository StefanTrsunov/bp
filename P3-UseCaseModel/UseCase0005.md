# Use-case 0005 — Place market SELL order

**Initiating actor:** Trader

**Other actors:** Market Simulator (indirect — supplies the current price).

A Trader sells part or all of a holding at the current market price. Cost basis is preserved so realised P/L can be reconstructed from the ledger.

## Scenario

1. Trader chooses "Place market SELL order".
2. System lists markets (same SQL as UC0004 step 2).
3. Trader enters market symbol and quantity.
4. System resolves the market and looks up the latest price (same SQL as UC0004 step 4).
5. System opens a transaction:

   ```sql
   BEGIN;

   INSERT INTO project.orders
       (user_id, market_id, side, type, status, quantity, price, executed_at)
   VALUES
       ($user_id, $market_id, 'sell', 'market', 'executed', $qty, $price, now())
   RETURNING id;   -- $order_id

   SELECT quantity, avg_price
     FROM project.holdings
    WHERE user_id = $user_id AND crypto_id = $crypto_id
    FOR UPDATE;
   -- abort if row missing or quantity < $qty
   ```
6. If the holding check passes, system reduces the holding, credits cash and debits invested, and appends a ledger and a market trade:

   ```sql
   UPDATE project.holdings
      SET quantity   = quantity - $qty,
          updated_at = now()
    WHERE user_id = $user_id AND crypto_id = $crypto_id;

   UPDATE project.users
      SET available_balance = available_balance + $notional,
          invested_balance  = GREATEST(invested_balance - ($avg_price * $qty), 0),
          updated_at        = now()
    WHERE id = $user_id;

   INSERT INTO project.transactions
       (user_id, type, amount, currency, related_order, description)
   VALUES
       ($user_id, 'sell', $notional, 'USD', $order_id, 'Market sell ...');

   INSERT INTO project.market_trades
       (market_id, executed_at, price, quantity, side, source)
   VALUES
       ($market_id, now(), $price, $qty, 'sell', 'user');

   COMMIT;
   ```
7. System confirms: `Order executed: sell 0.5000 ETH @ 3520.000000 (notional 1760.0000 USD)`.

### Alternate flow 5a — insufficient holding

If the `SELECT ... FOR UPDATE` returns no row, or the held quantity is smaller than the sell quantity, the entire transaction rolls back and system shows "Insufficient holding: trying to sell X, hold Y."

### Realised P/L (post-scenario)

The realised P/L for a sell is `$notional - ($avg_price * $qty)`. It is not persisted explicitly but can be computed from the ledger and the holding at sell time.
