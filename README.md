# EduBerza — quick start

Educational crypto-exchange simulator. Go CLI + PostgreSQL. Course project for
*Databases 2025/2026 Winter*, FINKI UKIM.


## Run it in four commands

```sh
cp .env.example .env          
docker compose up -d          
go build -o eduberza ./server
./eduberza -init              
./eduberza                    
```

Things to do:
Because we added one more table in Phase 7 I updated phase 1 and phase 2 `Order_events`
1. phase 2 update picture
2. In normalization P5
Modify and find a different way to do `Lossless join`
1. for phase 6 if wanted all points do Algebra
