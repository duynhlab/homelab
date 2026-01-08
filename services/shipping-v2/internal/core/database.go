package database

import (
	"database/sql"
	"fmt"
	"os"
	"strconv"

	_ "github.com/lib/pq" // PostgreSQL driver
	"go.uber.org/zap"
)

var (
	globalDB *sql.DB
	logger   *zap.Logger
)

// Connect establishes a database connection using environment variables
// Environment variables:
//   - DB_HOST: Database host (required)
//   - DB_PORT: Database port (default: 5432)
//   - DB_NAME: Database name (required)
//   - DB_USER: Database user (required)
//   - DB_PASSWORD: Database password (required)
//   - DB_SSLMODE: SSL mode (default: disable)
//   - DB_POOL_MAX_CONNECTIONS: Maximum connections (default: 25)
func Connect() (*sql.DB, error) {
	if globalDB != nil {
		return globalDB, nil
	}

	// Initialize logger
	var err error
	logger, err = zap.NewProduction()
	if err != nil {
		return nil, fmt.Errorf("failed to initialize logger: %w", err)
	}

	// Load configuration from environment variables
	host := os.Getenv("DB_HOST")
	port := getEnv("DB_PORT", "5432")
	name := os.Getenv("DB_NAME")
	user := os.Getenv("DB_USER")
	password := os.Getenv("DB_PASSWORD")
	sslmode := getEnv("DB_SSLMODE", "disable")
	maxConnections := getEnvInt("DB_POOL_MAX_CONNECTIONS", 25)

	// Validate required fields
	if host == "" {
		return nil, fmt.Errorf("DB_HOST is required")
	}
	if name == "" {
		return nil, fmt.Errorf("DB_NAME is required")
	}
	if user == "" {
		return nil, fmt.Errorf("DB_USER is required")
	}
	if password == "" {
		return nil, fmt.Errorf("DB_PASSWORD is required")
	}

	// Build DSN
	dsn := fmt.Sprintf("host=%s port=%s dbname=%s user=%s password=%s sslmode=%s",
		host, port, name, user, password, sslmode)

	// Open connection
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database connection: %w", err)
	}

	// Configure connection pool
	db.SetMaxOpenConns(maxConnections)
	db.SetMaxIdleConns(maxConnections / 2)
	db.SetConnMaxLifetime(0) // Connections don't expire

	// Test connection
	if err := db.Ping(); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	globalDB = db
	logger.Info("Database connection established",
		zap.String("host", host),
		zap.String("port", port),
		zap.String("database", name),
		zap.String("user", user),
		zap.Int("max_connections", maxConnections),
	)

	return globalDB, nil
}

// GetDB returns the global database connection
// Returns nil if Connect() has not been called or failed
func GetDB() *sql.DB {
	return globalDB
}

// Close closes the global database connection
func Close() error {
	if globalDB != nil {
		return globalDB.Close()
	}
	return nil
}

// Helper functions
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}
