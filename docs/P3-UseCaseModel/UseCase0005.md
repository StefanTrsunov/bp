# Use-case 0005 — Place market SELL order

**Initiating actor:** Trader

**Other actors:** Market Simulator (indirect — supplies the current price).

A Trader sells part or all of a holding at the current market price. Cost basis is preserved so realised P/L can be reconstructed from the ledger.

## Reserve, then settle

The crypto being sold is **reserved** (`holdings.reserved_quantity`) before it
is actually removed from the position, so the check a second sell order makes
is always against what is truly still free (`quantity - reserved_quantity`),
not against the raw `quantity`, which would also count crypto already
promised to this order. Because only market orders are implemented, an order
settles in the same database transaction it is placed in, so reserve and
settle below are two statements inside one commit rather than two separate
ones — the existing all-or-nothing guarantee (see
[PrototypeImplementation](../P4-Prototype/PrototypeImplementation.md)) is
kept. They stay logically distinct so that a future limit-order matcher —
where an order really would sit `open` for a while before a *later*
transaction settles it — needs only a second transaction where today there is
one, not a schema change.

## Scenario

1. Trader chooses "Place market SELL order".
2. System lists, numbered, the Trader's holdings that still have a quantity free to
   sell (not reserved by an open sell order), with the quantity held, the free
   quantity and the latest price:

   ```sql
   SELECT m.id, c.id, c.symbol, m.quote_currency,
          h.quantity, h.quantity - h.reserved_quantity AS free,
          COALESCE(lp.price, 0) AS price
     FROM project.holdings h
     JOIN project.crypto  c ON c.id = h.crypto_id
     JOIN project.markets m ON m.crypto_id = c.id AND m.is_active = true
     LEFT JOIN project.v_latest_prices lp ON lp.market_id = m.id
    WHERE h.user_id = $1
      AND h.quantity - h.reserved_quantity > 0
    ORDER BY c.symbol;
   ```
3. Trader picks the holding by its number in the listed holdings, e.g. `2` (ETH), and
   enters the quantity.
4. System takes the chosen row's market id and crypto id from the list (no lookup by
   symbol) and looks up the latest price:

   ```sql
   SELECT price FROM project.v_latest_prices WHERE market_id = $1;
   ```
5. System opens a transaction:

   ```sql
   BEGIN;

   -- (a) record intent — no trade has happened yet.
   INSERT INTO project.orders
       (user_id, market_id, side, type, status, quantity, price)
   VALUES
       ($user_id, $market_id, 'sell', 'market', 'open', $qty, $price)
   RETURNING id;   -- $order_id

   -- (b) lock the holding and check what is actually free to sell.
   SELECT quantity, reserved_quantity, avg_price
     FROM project.holdings
    WHERE user_id = $user_id AND crypto_id = $crypto_id
    FOR UPDATE;
   -- available := quantity - reserved_quantity
   -- abort if row missing or available < $qty
   ```

6. If the check passes, system reserves the crypto, then — since this is a market order — settles it immediately, all inside the same transaction:

   ```sql
   -- (c) reserve: committed to this order, not yet removed from the position.
   UPDATE project.holdings
      SET reserved_quantity = reserved_quantity + $qty,
          updated_at        = now()
    WHERE user_id = $user_id AND crypto_id = $crypto_id;

   -- (d) settle: release the reservation and remove the asset in one step.
   UPDATE project.holdings
      SET quantity          = quantity - $qty,
          reserved_quantity = reserved_quantity - $qty,
          updated_at        = now()
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

   -- (e) settle the order itself — it has now actually been filled.
   UPDATE project.orders
      SET status = 'executed', executed_at = now()
    WHERE id = $order_id;

   COMMIT;
   ```

7. System confirms: `Order executed: sell 0.5000 ETH @ 3520.000000 (notional 1760.0000 USD)`.

### Alternate flow 5a — insufficient holding

If the holding row is missing, or `quantity - reserved_quantity < $qty`, the
entire transaction rolls back — including the `open` order from step 5, which
was never committed — and system shows:
`"Insufficient holding: trying to sell X, available Y (of Z held, W reserved)."`

### Worked example — the case this fixes

Alice holds 2 BTC, `reserved_quantity = 0`, and places `sell 0.5 BTC`:

| | quantity | reserved_quantity | available |
|---|---|---|---|
| before | 2.0000 | 0.0000 | 2.0000 |
| after step (c) — reserved | 2.0000 | 0.5000 | 1.5000 |
| after step (d) — settled | 1.5000 | 0.0000 | 1.5000 |

If a second sell for more than 1.5 BTC is placed concurrently, its own
`SELECT … FOR UPDATE` in step 5b blocks until the first transaction commits,
then sees the reduced `quantity` and correctly reports insufficient holding —
proven under real concurrency in
[UseCase0005Implementation](../P4-Prototype/UseCase0005Implementation.md).

### Realised P/L (post-scenario)

The realised P/L for a sell is `$notional - ($avg_price * $qty)`. It is not persisted explicitly but can be computed from the ledger and the holding at sell time.
