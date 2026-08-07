# Use-case 0004 — Place market BUY order

**Initiating actor:** Trader

**Other actors:** Market Simulator (indirect — supplies the current price via `market_trades`).

A Trader buys a crypto asset at the current market price. The operation touches five tables (`orders`, `users`, `holdings`, `transactions`, `market_trades`) and must either all succeed or all roll back.

## Scenario

1. Trader chooses "Place market BUY order".
2. System lists the available markets with their latest price:

   ```sql
   SELECT m.id, c.symbol, m.quote_currency, COALESCE(lp.price, 0)
     FROM project.markets m
     JOIN project.crypto  c  ON c.id = m.crypto_id
     LEFT JOIN project.v_latest_prices lp ON lp.market_id = m.id
    WHERE m.is_active = true
    ORDER BY c.symbol;
   ```
3. Trader enters a market symbol, e.g. `ETH`.
4. System resolves the market and looks up the latest price:

   ```sql
   SELECT m.id, c.id AS crypto_id, c.symbol, m.quote_currency
     FROM project.markets m
     JOIN project.crypto c ON c.id = m.crypto_id
    WHERE upper(c.symbol) = upper($1) AND m.is_active = true;

   SELECT price FROM project.v_latest_prices WHERE market_id = $2;
   ```
5. Trader enters a quantity.
6. System computes notional = quantity × price, opens a transaction, and does:

   ```sql
   BEGIN;

   INSERT INTO project.orders
       (user_id, market_id, side, type, status, quantity, price, executed_at)
   VALUES
       ($user_id, $market_id, 'buy', 'market', 'executed', $qty, $price, now())
   RETURNING id;  -- captured as $order_id

   SELECT available_balance FROM project.users WHERE id = $user_id FOR UPDATE;
   -- abort if available_balance < notional

   UPDATE project.users
      SET available_balance = available_balance - $notional,
          invested_balance  = invested_balance  + $notional,
          updated_at        = now()
    WHERE id = $user_id;

   -- Upsert holding with running weighted-average price:
   SELECT quantity, avg_price
     FROM project.holdings
    WHERE user_id = $user_id AND crypto_id = $crypto_id
    FOR UPDATE;

   -- Either INSERT (new holding) or UPDATE (existing), computing
   -- new_avg = (old_qty*old_avg + $qty*$price) / (old_qty + $qty)

   INSERT INTO project.transactions
       (user_id, type, amount, currency, related_order, description)
   VALUES
       ($user_id, 'buy', -$notional, 'USD', $order_id, 'Market buy ...');

   INSERT INTO project.market_trades
       (market_id, executed_at, price, quantity, side, source)
   VALUES
       ($market_id, now(), $price, $qty, 'buy', 'user');

   COMMIT;
   ```
7. System confirms: `Order executed: buy 0.0100 BTC @ 67140.000000 (notional 671.4000 USD)`.

### Alternate flow 6a — insufficient funds

If `available_balance < notional`, the entire transaction rolls back and system shows "Insufficient funds: need X, have Y."

### Alternate flow 4a — market not found

If the entered symbol does not match any active market, system shows "market X not found" and returns to the authenticated menu without opening a transaction.
