package domain

// Transaction represents a database transaction for cart operations
type Transaction interface {
	Commit() error
	Rollback() error
}
