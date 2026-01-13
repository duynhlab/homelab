package domain

import "context"

// Transaction represents a database transaction
type Transaction interface {
	Commit() error
	Rollback() error
}

// TransactionManager manages database transactions
type TransactionManager interface {
	Begin(ctx context.Context) (Transaction, error)
}
