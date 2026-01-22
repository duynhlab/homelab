package database

import (
	"context"
	"fmt"
	"os"
	"strconv"

	"github.com/jackc/pgx/v5/pgxpool"
)

// DatabaseConfig holds database connection configuration
// loaded from environment variables
type DatabaseConfig struct {
	Host           string // DB_HOST - PostgreSQL host (e.g., "pgdog-product.product.svc.cluster.local")
	Port           string // DB_PORT - PostgreSQL port (default: 5432)
	Name           string // DB_NAME - Database name (e.g., "product")
	User           string // DB_USER - Database user
	Password       string // DB_PASSWORD - Database password
	SSLMode        string // DB_SSLMODE - SSL mode (disable/require/verify-full)
	MaxConnections int    // DB_POOL_MAX_CONNECTIONS - Max pool connections (default: 25)
}

// globalPool is the shared connection pool for the application
// Initialized once by Connect(), accessed via GetPool()
var globalPool *pgxpool.Pool

// LoadConfig loads database configuration from environment variables.
// Returns error if required variables (HOST, NAME, USER, PASSWORD) are missing.
func LoadConfig() (*DatabaseConfig, error) {
	cfg := &DatabaseConfig{
		Host:           getEnv("DB_HOST", ""),
		Port:           getEnv("DB_PORT", "5432"),
		Name:           getEnv("DB_NAME", ""),
		User:           getEnv("DB_USER", ""),
		Password:       getEnv("DB_PASSWORD", ""),
		SSLMode:        getEnv("DB_SSLMODE", "disable"),
		MaxConnections: getEnvInt("DB_POOL_MAX_CONNECTIONS", 25),
	}

	// Validate required environment variables
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

// BuildDSN constructs PostgreSQL connection string (DSN) from config.
// Format: postgresql://user:password@host:port/dbname?sslmode=X&pool_max_conns=N
//
// Note: pool_max_conns is a pgxpool-specific parameter that configures
// the maximum number of connections in the pool.
func (c *DatabaseConfig) BuildDSN() string {
	return fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=%s&pool_max_conns=%d",
		c.User, c.Password, c.Host, c.Port, c.Name, c.SSLMode, c.MaxConnections,
	)
}

// Connect establishes database connection pool using pgx/v5.
//
// Why pgx instead of lib/pq?
// - pgx uses client-side prepared statements, compatible with PgDog/PgBouncer
// - lib/pq uses server-side prepared statements which cause errors with connection poolers
// - pgxpool provides built-in connection pooling optimized for PostgreSQL
//
// The pool is stored globally and can be retrieved via GetPool().
func Connect(ctx context.Context) (*pgxpool.Pool, error) {
	cfg, err := LoadConfig()
	if err != nil {
		return nil, fmt.Errorf("failed to load database config: %w", err)
	}

	// Create connection pool with pgx
	// pgxpool.New parses the DSN and creates a pool with the specified max connections
	pool, err := pgxpool.New(ctx, cfg.BuildDSN())
	if err != nil {
		return nil, fmt.Errorf("failed to create connection pool: %w", err)
	}

	// Verify connection is working
	if err := pool.Ping(ctx); err != nil {
		pool.Close() // Clean up on failure
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	// Store global reference for GetPool()
	globalPool = pool

	return pool, nil
}

// GetPool returns the global connection pool.
// Must call Connect() first, otherwise returns nil.
func GetPool() *pgxpool.Pool {
	return globalPool
}

// GetDB is an alias for GetPool() - provided for backward compatibility
// Deprecated: Use GetPool() for new code
func GetDB() *pgxpool.Pool {
	return globalPool
}

// getEnv retrieves environment variable or returns default value
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvInt retrieves environment variable as integer or returns default value
func getEnvInt(key string, defaultValue int) int {
	if val := os.Getenv(key); val != "" {
		if intVal, err := strconv.Atoi(val); err == nil {
			return intVal
		}
	}
	return defaultValue
}
