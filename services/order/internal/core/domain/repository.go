package domain

import "context"

// OrderRepository defines the interface for order data access
type OrderRepository interface {
	FindByID(ctx context.Context, id string) (*Order, error)
	FindByUserID(ctx context.Context, userID string) ([]Order, error)
	Create(ctx context.Context, order *Order) error
	UpdateStatus(ctx context.Context, id, status string) error

	// Transaction support
	CreateWithTx(ctx context.Context, tx Transaction, order *Order) error
}
