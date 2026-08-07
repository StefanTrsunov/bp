package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"

	"bp_project/server/db"
)

func hashPassword(pw string) string {
	sum := sha256.Sum256([]byte(pw))
	return hex.EncodeToString(sum[:])
}

// Register - UC0001
func Register() {
	fmt.Println("\n-- Register --")
	username := prompt("Username: ")
	email := prompt("Email: ")
	fullName := prompt("Full name: ")
	pw := prompt("Password (min 6 chars): ")

	if username == "" || email == "" || pw == "" {
		fmt.Println("Username, email and password are required.")
		return
	}
	if !strings.Contains(email, "@") {
		fmt.Println("Invalid email.")
		return
	}
	if len(pw) < 6 {
		fmt.Println("Password must be at least 6 characters.")
		return
	}

	var exists bool
	err := db.DB.QueryRow(
		`SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 OR email = $2)`,
		username, email,
	).Scan(&exists)
	if err != nil {
		fmt.Println("Database error:", err)
		return
	}
	if exists {
		fmt.Println("Username or email already taken.")
		return
	}

	_, err = db.DB.Exec(
		`INSERT INTO users (username, email, full_name, password_hash, available_balance)
		 VALUES ($1, $2, $3, $4, 0)`,
		username, email, fullName, hashPassword(pw),
	)
	if err != nil {
		fmt.Println("Failed to register:", err)
		return
	}
	fmt.Println("Account created. You can now log in.")
}

// Login - UC0002
func Login(s *Session) {
	fmt.Println("\n-- Login --")
	username := prompt("Username: ")
	pw := prompt("Password: ")
	if username == "" || pw == "" {
		fmt.Println("Username and password are required.")
		return
	}

	id, err := authenticate(username, pw)
	if err != nil {
		if errors.Is(err, errInvalidCreds) {
			fmt.Println("Invalid credentials.")
			return
		}
		fmt.Println("Login error:", err)
		return
	}
	s.UserID = id
	s.Username = username
	fmt.Println("Login successful.")
}

var errInvalidCreds = errors.New("invalid credentials")

func authenticate(username, pw string) (string, error) {
	var id, stored string
	err := db.DB.QueryRow(
		`SELECT id, password_hash FROM users WHERE username = $1`,
		username,
	).Scan(&id, &stored)
	if err == sql.ErrNoRows {
		return "", errInvalidCreds
	}
	if err != nil {
		return "", err
	}
	if stored != hashPassword(pw) {
		return "", errInvalidCreds
	}
	return id, nil
}
