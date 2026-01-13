package repository

import (
	"context"
	"database/sql"

	"github.com/duynhne/monitoring/services/order/internal/core/domain"
)

// PostgresTransactionManager implements TransactionManager using PostgreSQL
type PostgresTransactionManager struct {
	db *sql.DB
}

// NewPostgresTransactionManager creates a new PostgreSQL transaction manager
func NewPostgresTransactionManager(db *sql.DB) *PostgresTransactionManager {
	return &PostgresTransactionManager{db: db}
}

// Begin starts a new database transaction
func (tm *PostgresTransactionManager) Begin(ctx context.Context) (domain.Transaction, error) {
	tx, err := tm.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	return &PostgresTransaction{tx: tx}, nil
}

// PostgresTransaction implements Transaction using PostgreSQL
type PostgresTransaction struct {
	tx *sql.Tx
}

// Commit commits the transaction
func (t *PostgresTransaction) Commit() error {
	return t.tx.Commit()
}

// Rollback rolls back the transaction
func (t *PostgresTransaction) Rollback() error {
	return t.tx.Rollback()
}
