package database

import (
	"database/sql"
	"fmt"
	"os"
	"strconv"

	_ "github.com/lib/pq" // PostgreSQL driver
)

// DatabaseConfig holds database connection configuration
type DatabaseConfig struct {
	Host           string
	Port           string
	Name           string
	User           string
	Password       string
	SSLMode        string
	MaxConnections int
	PoolMode       string
}

var globalDB *sql.DB

// LoadConfig loads database configuration from separate environment variables
func LoadConfig() (*DatabaseConfig, error) {
	cfg := &DatabaseConfig{
		Host:           getEnv("DB_HOST", ""),
		Port:           getEnv("DB_PORT", "5432"),
		Name:           getEnv("DB_NAME", ""),
		User:           getEnv("DB_USER", ""),
		Password:       getEnv("DB_PASSWORD", ""),
		SSLMode:        getEnv("DB_SSLMODE", "disable"),
		MaxConnections: getEnvInt("DB_POOL_MAX_CONNECTIONS", 25),
		PoolMode:       getEnv("DB_POOL_MODE", "transaction"),
	}

	// Validate required fields
	if cfg.Host == "" {
		return nil, fmt.Errorf("DB_HOST environment variable is required")
	}
	if cfg.Name == "" {
		return nil, fmt.Errorf("DB_NAME environment variable is required")
	}
	if cfg.User == "" {
		return nil, fmt.Errorf("DB_USER environment variable is required")
	}
	if cfg.Password == "" {
		return nil, fmt.Errorf("DB_PASSWORD environment variable is required")
	}

	return cfg, nil
}

// BuildDSN constructs PostgreSQL connection string from config
func (c *DatabaseConfig) BuildDSN() string {
	// Format: postgresql://user:password@host:port/dbname?sslmode=disable
	return fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=%s",
		c.User,
		c.Password,
		c.Host,
		c.Port,
		c.Name,
		c.SSLMode,
	)
}

// Connect establishes database connection using separate environment variables
func Connect() (*sql.DB, error) {
	// ⚠️ CRITICAL: Load config from separate env vars, NOT DATABASE_URL string
	cfg, err := LoadConfig()
	if err != nil {
		return nil, fmt.Errorf("failed to load database config: %w", err)
	}

	// Build DSN from individual env vars
	dsn := cfg.BuildDSN()

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Configure connection pool
	db.SetMaxOpenConns(cfg.MaxConnections)
	db.SetMaxIdleConns(cfg.MaxConnections / 2)

	// Test connection
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	// Store global connection
	globalDB = db

	return db, nil
}

// GetDB returns the global database connection
func GetDB() *sql.DB {
	return globalDB
}

// Helper functions
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if val := os.Getenv(key); val != "" {
		if intVal, err := strconv.Atoi(val); err == nil {
			return intVal
		}
	}
	return defaultValue
}
