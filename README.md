# EduBerza — quick start

Educational crypto-exchange simulator. Go CLI + PostgreSQL. Course project for
*Databases 2025/2026 Winter*, FINKI UKIM.

Full documentation lives in [`docs/`](docs/) — start at [`docs/README.md`](docs/README.md),
which is the project front page and links every phase. Detailed build and test
instructions are in [`docs/P4-Prototype/BuildInstructions.md`](docs/P4-Prototype/BuildInstructions.md).

## Run it in four commands

```sh
cp .env.example .env          # local defaults: postgres on port 5433
docker compose up -d          # start PostgreSQL
go build -o eduberza ./server
./eduberza -init              # create the `project` schema + load sample data
./eduberza                    # start the CLI
```

Log in as `alice` / `test123` (also `bob`, `charlie` — same password).

`./eduberza -init` is destructive and idempotent: it drops and recreates the
`project` schema every time, so it is the reset button whenever a demo goes
sideways. `./eduberza -load-data` reloads only the sample data.

Optional — watch prices move while you trade, in a second terminal:

```sh
go run ./bots
```

## Layout

| Path | What |
|------|------|
| `server/` | CLI prototype — one file per use-case area |
| `server/db/schema_creation.sql` | DDL: drops + recreates the `project` schema (P2) |
| `server/db/data_load.sql` | DML: truncates + reloads sample data (P2) |
| `bots/` | Market simulation bot — random-walk trades and 1m candles |
| `docs/` | All phase documentation, ER diagram, use cases |

Both SQL scripts are embedded into the binary at build time, so `-init` works
from any working directory.

## Requirements

Go 1.25+, Docker (or any reachable PostgreSQL 14+), and optionally `psql`.
Editing the ER diagram additionally needs Java and TerraER — see
[`docs/P4-Prototype/BuildInstructions.md`](docs/P4-Prototype/BuildInstructions.md).
