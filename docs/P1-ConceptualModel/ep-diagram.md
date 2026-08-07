Ентитети

User – ентитет кој чува информации за корисниците на платформата

id (uuid)

username (varchar(50), not null, unique)

email (varchar(255), not null, unique)

password_hash (varchar(255), not null)

full_name (varchar(200))

created_at (timestamptz)

updated_at (timestamptz)


Crypto – ентитет кој ги чува податоците за криптовалутите со кои се тргува

id (uuid)

symbol (varchar(20), not null, unique)

name (varchar(255))

created_at (timestamptz)



Market – ентитет кој ги дефинира пазарите (парови криптовалути и валути за котација(BTCUSDT, ADAUSDT, ADABTC))

id (uuid)

crypto_id (uuid, not null, FK → Crypto.id)

quote_currency (char(3), not null) ADA, USDT, BTC, USDT

is_active (boolean)

created_at (timestamptz)



Holding – ентитет кој ги чува позициите на корисниците во криптовалути

id (uuid)

user_id (uuid, not null, FK → User.id)

crypto_id (uuid, not null, FK → Crypto.id)

quantity (numeric(20,4), not null)

avg_price (numeric(18,6))

created_at (timestamptz)

updated_at (timestamptz)



Order – ентитет кој ги чува нарачките за купување/продавање

id (uuid)

user_id (uuid, not null, FK → User.id)

market_id (uuid, not null, FK → Market.id)

side (varchar(4), not null) — типично “buy” или “sell”

type (varchar(20), not null) — тип на нарачка, пример “limit”, “market”

status (varchar(20), not null) — статус на нарачка (open, executed, cancelled)

quantity (numeric(20,4), not null)

price (numeric(18,6))

placed_at (timestamptz)

executed_at (timestamptz)



Transaction – ентитет кој ја следи финансиската активност на корисниците (депозити, купувања, продавања, провизии)

id (uuid)

user_id (uuid, not null, FK → User.id)

type (varchar(50), not null) — пример: “deposit”, “buy”, “sell”, “fee”

amount (numeric(18,4), not null)

currency (char(3), not null)

related_order (uuid, FK → Order.id)

created_at (timestamptz)

description (text)



Market_Trade – ентитет кој ги евидентира извршените пазарни зделки кои ја формираат цената

id (bigserial)

market_id (uuid, not null, FK → Market.id)

executed_at (timestamptz, not null)

price (numeric(18,6), not null)

quantity (numeric(20,6), not null)

side (varchar(4))

source (varchar(50))

Market_Candle – ентитет кој ги агрегира податоците за цените и волуменот во временски интервали (целови)

id (bigserial)

market_id (uuid, not null, FK → Market.id)

timeframe (varchar(5), not null) — пример: “1m”, “5m”, “1h”

open (numeric(18,6), not null)

high (numeric(18,6), not null)

low (numeric(18,6), not null)

close (numeric(18,6), not null)

volume (numeric(20,6), not null)

candle_time (timestamptz, not null)

Watchlist – ентитет кој ги чува листите за следење на корисниците

id (uuid)

user_id (uuid, not null, FK → User.id)

name (varchar(100))

created_at (timestamptz)

Watchlist_Item – ентитет кој ги чува криптовалутите кои се ставени во некоја листа за следење

id (uuid)

watchlist_id (uuid, not null, FK → Watchlist.id)

crypto_id (uuid, not null, FK → Crypto.id)

added_at (timestamptz)

Релации

User – Holding (1:N)
Еден корисник може да има повеќе позиции во различни криптовалути.

Crypto – Holding (1:N)
Една криптовалута може да се држи од повеќе корисници.

User – Order (1:N)
Еден корисник може да има повеќе нарачки.

Market – Order (1:N)
Еден пазар има повеќе нарачки.

User – Transaction (1:N)
Еден корисник има повеќе трансакции.

Order – Transaction (0..1 : N)
Трансакцијата може да биде поврзана со една нарачка (пример купување/продажба).

Market – Market_Trade (1:N)
Еден пазар има многу извршени зделки.

Market – Market_Candle (1:N)
Еден пазар има многу временски агрегирани податоци.

User – Watchlist (1:N)
Еден корисник може да има повеќе листи за следење.

Watchlist – Watchlist_Item (1:N)
Една листа може да содржи повеќе криптовалути.

Crypto – Watchlist_Item (1:N)
Една криптовалута може да биде во повеќе листи за следење.