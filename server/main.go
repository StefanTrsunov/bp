package main

import (
	"flag"
	"fmt"
	"log"

	"bp_project/server/db"
)

func main() {
	initFlag := flag.Bool("init", false, "drop and recreate the project schema, then load sample data")
	loadData := flag.Bool("load-data", false, "reload sample data (without dropping schema)")
	flag.Parse()

	if err := db.Connect(); err != nil {
		log.Fatalf("database connect failed: %v", err)
	}
	defer db.DB.Close()

	if *initFlag {
		if err := db.InitSchema(); err != nil {
			log.Fatalf("init failed: %v", err)
		}
		fmt.Println("Schema initialised. Re-run without -init to start the CLI.")
		return
	}
	if *loadData {
		if err := db.LoadData(); err != nil {
			log.Fatalf("data load failed: %v", err)
		}
		fmt.Println("Sample data reloaded.")
		return
	}

	RunCLI()
}
