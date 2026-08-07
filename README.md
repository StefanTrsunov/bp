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