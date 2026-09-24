# Use-case 0007 — Manage watchlist

**Initiating actor:** Trader

**Other actors:** —

A Trader keeps a list of crypto assets they want to monitor. Adding an asset that is already on the list is a no-op (idempotent).

## Scenario

1. Trader chooses "Manage watchlist".
2. System ensures the Trader has a default watchlist named "Favorites":

   ```sql
   SELECT id FROM project.watchlists
    WHERE user_id = $1
    ORDER BY created_at LIMIT 1;

   -- if no row:
   INSERT INTO project.watchlists (user_id, name)
   VALUES ($1, 'Favorites')
   RETURNING id;
   ```
3. System shows the sub-menu: List / Add / Remove / Back.

### List items

```sql
SELECT c.symbol, c.name, COALESCE(lp.price, 0)
  FROM project.watchlist_items wi
  JOIN project.crypto c ON c.id = wi.crypto_id
  LEFT JOIN project.markets m
         ON m.crypto_id = c.id AND m.quote_currency = 'USD'
  LEFT JOIN project.v_latest_prices lp
         ON lp.market_id = m.id
 WHERE wi.watchlist_id = $1
 ORDER BY c.symbol;
```

### Add a crypto

The Trader picks the crypto by its number from the listed cryptos that are not on the watchlist yet:

```sql
-- 1. list, numbered, the cryptos not yet on the watchlist
SELECT c.id, c.symbol, c.name
  FROM project.crypto c
 WHERE NOT EXISTS (SELECT 1 FROM project.watchlist_items wi
                    WHERE wi.watchlist_id = $1 AND wi.crypto_id = c.id)
 ORDER BY c.symbol;

-- 2. insert the chosen crypto ($2 = its id from the list); do nothing if it's already there
INSERT INTO project.watchlist_items (watchlist_id, crypto_id)
VALUES ($1, $2)
ON CONFLICT (watchlist_id, crypto_id) DO NOTHING;
```

### Remove a crypto

The Trader picks the crypto by its number from the listed cryptos on the watchlist:

```sql
-- 1. list, numbered, the cryptos on the watchlist
SELECT c.id, c.symbol, c.name
  FROM project.watchlist_items wi
  JOIN project.crypto c ON c.id = wi.crypto_id
 WHERE wi.watchlist_id = $1
 ORDER BY c.symbol;

-- 2. delete the chosen crypto ($2 = its id from the list)
DELETE FROM project.watchlist_items
 WHERE watchlist_id = $1 AND crypto_id = $2;
```

If the entered number is not one of the listed numbers, system shows "Invalid choice, enter a number from 1 to N." and nothing is changed.
