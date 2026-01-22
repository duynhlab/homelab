package repository

import (
	"context"

	"github.com/duynhne/monitoring/services/order/internal/core/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresTransactionManager implements TransactionManager using PostgreSQL with pgx
type PostgresTransactionManager struct {
	pool *pgxpool.Pool
}

// NewPostgresTransactionManager creates a new PostgreSQL transaction manager
func NewPostgresTransactionManager(pool *pgxpool.Pool) *PostgresTransactionManager {
	return &PostgresTransactionManager{pool: pool}
}

// Begin starts a new database transaction
func (tm *PostgresTransactionManager) Begin(ctx context.Context) (domain.Transaction, error) {
	tx, err := tm.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	return &PostgresTransaction{tx: tx}, nil
}

// PostgresTransaction implements Transaction using PostgreSQL with pgx
type PostgresTransaction struct {
	tx pgx.Tx
}

// Commit commits the transaction
func (t *PostgresTransaction) Commit(ctx context.Context) error {
	return t.tx.Commit(ctx)
}

// Rollback rolls back the transaction
func (t *PostgresTransaction) Rollback(ctx context.Context) error {
	return t.tx.Rollback(ctx)
}

// QueryRow executes a query that returns a single row
func (t *PostgresTransaction) QueryRow(ctx context.Context, query string, args ...interface{}) pgx.Row {
	return t.tx.QueryRow(ctx, query, args...)
}

// Exec executes a query that doesn't return rows
func (t *PostgresTransaction) Exec(ctx context.Context, query string, args ...interface{}) error {
	_, err := t.tx.Exec(ctx, query, args...)
	return err
}
