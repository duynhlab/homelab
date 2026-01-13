package domain

import "context"

// CartRepository defines the interface for cart data access
type CartRepository interface {
	// Cart operations
	FindByUserID(ctx context.Context, userID string) (*Cart, error)
	GetItemCount(ctx context.Context, userID string) (int, error)

	// Item operations
	AddItem(ctx context.Context, userID string, item CartItem) error
	UpdateItem(ctx context.Context, userID, itemID string, quantity int) error
	RemoveItem(ctx context.Context, userID, itemID string) error
	Clear(ctx context.Context, userID string) error
}
