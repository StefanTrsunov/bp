// EduBerza market simulation bot.
//
// Walks a small price for every active market, inserts rows into
// market_trades once per tick, and upserts the current 1m candle.
//
// Run from the repo root so the relative .env path resolves:
//
//	go run ./bots/...
package main

import (
	"bufio"
	"database/sql"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"os"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

type market struct {
	id     string
	symbol string
	price  float64
}

func main() {
	interval := flag.Duration("interval", 3*time.Second, "seconds between price ticks")
	flag.Parse()

	loadEnv(".env")
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable options='--search_path=project,public'",
		env("DBHOST", "localhost"),
		env("DBPORT", "5432"),
		env("DBUSER", "postgres"),
		env("DBPASSWORD", ""),
		env("DBNAME", "postgres"),
	)
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer db.Close()
	if err := db.Ping(); err != nil {
		log.Fatalf("ping: %v", err)
	}

	markets, err := loadMarkets(db)
	if err != nil {
		log.Fatalf("load markets: %v", err)
	}
	if len(markets) == 0 {
		log.Fatal("no active markets found - run `go run ./server -init` first")
	}

	log.Printf("bot started. simulating %d markets every %s", len(markets), *interval)
	rnd := rand.New(rand.NewSource(time.Now().UnixNano()))

	for {
		for i := range markets {
			m := &markets[i]
			// random walk: ±0.3% per tick
			drift := (rnd.Float64() - 0.5) * 0.006
			m.price = m.price * (1 + drift)
			if m.price <= 0 {
				m.price = 0.000001
			}
			qty := rnd.Float64()*0.5 + 0.01

			side := "buy"
			if rnd.Float64() < 0.5 {
				side = "sell"
			}

			if err := insertTick(db, m.id, m.price, qty, side); err != nil {
				log.Printf("insert tick %s: %v", m.symbol, err)
				continue
			}
			log.Printf("  %-8s  %.6f  qty=%.4f  side=%s", m.symbol, m.price, qty, side)
		}
		time.Sleep(*interval)
	}
}

func loadMarkets(db *sql.DB) ([]market, error) {
	rows, err := db.Query(`
		SELECT m.id, c.symbol, COALESCE(lp.price, 100)
		  FROM markets m
		  JOIN crypto  c  ON c.id = m.crypto_id
		  LEFT JOIN v_latest_prices lp ON lp.market_id = m.id
		 WHERE m.is_active = true
		 ORDER BY c.symbol`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []market
	for rows.Next() {
		var m market
		if err := rows.Scan(&m.id, &m.symbol, &m.price); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, nil
}

func insertTick(db *sql.DB, marketID string, price, qty float64, side string) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(
		`INSERT INTO market_trades (market_id, executed_at, price, quantity, side, source)
		 VALUES ($1, now(), $2, $3, $4, 'simulation')`,
		marketID, price, qty, side,
	); err != nil {
		return err
	}

	// upsert the current 1m candle
	if _, err := tx.Exec(`
		INSERT INTO market_candles (market_id, timeframe, open, high, low, close, volume, candle_time)
		VALUES ($1, '1m', $2, $2, $2, $2, $3, date_trunc('minute', now()))
		ON CONFLICT (market_id, timeframe, candle_time) DO UPDATE
		   SET high   = GREATEST(market_candles.high, EXCLUDED.close),
		       low    = LEAST(   market_candles.low,  EXCLUDED.close),
		       close  = EXCLUDED.close,
		       volume = market_candles.volume + EXCLUDED.volume`,
		marketID, price, qty,
	); err != nil {
		return err
	}
	return tx.Commit()
}

func loadEnv(path string) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()
	s := bufio.NewScanner(f)
	for s.Scan() {
		line := strings.TrimSpace(s.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			os.Setenv(strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1]))
		}
	}
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
