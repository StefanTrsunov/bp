package db

import (
	"bufio"
	"database/sql"
	"embed"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	_ "github.com/lib/pq"
)

var DB *sql.DB

// The SQL scripts are compiled into the binary so that -init works no matter
// which directory the program is started from.
//
//go:embed schema_creation.sql data_load.sql
var sqlScripts embed.FS

func Connect() error {
	loadEnvFile()

	host := getenv("DBHOST", "localhost")
	port := getenv("DBPORT", "5432")
	user := getenv("DBUSER", "postgres")
	pass := getenv("DBPASSWORD", "")
	name := getenv("DBNAME", "postgres")

	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable options='--search_path=project,public'",
		host, port, user, pass, name,
	)

	var err error
	DB, err = sql.Open("postgres", dsn)
	if err != nil {
		return fmt.Errorf("sql.Open: %w", err)
	}
	if err := DB.Ping(); err != nil {
		return fmt.Errorf("db ping (host=%s port=%s user=%s dbname=%s): %w",
			host, port, user, name, err)
	}
	return nil
}

// runScript executes one of the embedded .sql scripts as a single statement.
func runScript(name string) error {
	content, err := sqlScripts.ReadFile(name)
	if err != nil {
		return fmt.Errorf("read embedded %s: %w", name, err)
	}
	if _, err := DB.Exec(string(content)); err != nil {
		return fmt.Errorf("exec %s: %w", name, err)
	}
	return nil
}

// RunSQLFile executes a .sql file from disk as a single statement.
func RunSQLFile(path string) error {
	content, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read %s: %w", path, err)
	}
	if _, err := DB.Exec(string(content)); err != nil {
		return fmt.Errorf("exec %s: %w", path, err)
	}
	return nil
}

// InitSchema runs schema_creation.sql then data_load.sql.
// Destructive: drops the `project` schema. Intended for the -init flag.
func InitSchema() error {
	log.Println("Running schema_creation.sql ...")
	if err := runScript("schema_creation.sql"); err != nil {
		return err
	}
	if err := LoadData(); err != nil {
		return err
	}
	log.Println("Database initialised.")
	return nil
}

// LoadData reloads the sample data without touching the schema.
func LoadData() error {
	log.Println("Running data_load.sql ...")
	return runScript("data_load.sql")
}

// loadEnvFile looks for a .env file in the working directory and in every
// parent directory, so the program can be started from the repo root, from
// server/, or from anywhere else inside the checkout. Variables already set
// in the real environment always win over the file, which is what lets you
// point the prototype at the faculty database with DBHOST=... ./eduberza
func loadEnvFile() {
	dir, err := os.Getwd()
	if err != nil {
		return
	}
	for {
		path := filepath.Join(dir, ".env")
		if applyEnvFile(path) {
			return
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return // reached the filesystem root
		}
		dir = parent
	}
}

// applyEnvFile reports whether the file existed and was read.
func applyEnvFile(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()

	s := bufio.NewScanner(f)
	for s.Scan() {
		line := strings.TrimSpace(s.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		// Do not clobber variables that are already set in the environment.
		if _, exists := os.LookupEnv(key); exists {
			continue
		}
		os.Setenv(key, strings.Trim(strings.TrimSpace(value), `"'`))
	}
	if err := s.Err(); err != nil {
		log.Printf("warning: could not fully read %s: %v", path, err)
	}
	return true
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
