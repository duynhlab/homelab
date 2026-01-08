package repository

import (
	"context"
	"database/sql"

	"github.com/duynhne/monitoring/services/cart/internal/core/domain"
)

// PostgresCartRepository implements CartRepository using PostgreSQL
type PostgresCartRepository struct {
	db *sql.DB
}

// NewPostgresCartRepository creates a new PostgreSQL cart repository
func NewPostgresCartRepository(db *sql.DB) *PostgresCartRepository {
	return &PostgresCartRepository{db: db}
}

// FindByUserID retrieves a cart by user ID
func (r *PostgresCartRepository) FindByUserID(ctx context.Context, userID string) (*domain.Cart, error) {
	// Get cart items
	query := `
		SELECT ci.id, ci.product_id, p.name, p.price, ci.quantity
		FROM cart_items ci
		JOIN products p ON ci.product_id = p.id
		WHERE ci.user_id = $1
	`

	rows, err := r.db.QueryContext(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []domain.CartItem
	var subtotal float64

	for rows.Next() {
		var item domain.CartItem
		err := rows.Scan(&item.ID, &item.ProductID, &item.ProductName, &item.ProductPrice, &item.Quantity)
		if err != nil {
			continue
		}
		item.Subtotal = item.ProductPrice * float64(item.Quantity)
		subtotal += item.Subtotal
		items = append(items, item)
	}

	cart := &domain.Cart{
		UserID:    userID,
		Items:     items,
		Subtotal:  subtotal,
		Shipping:  5.00, // Fixed shipping cost for demo
		Total:     subtotal + 5.00,
		ItemCount: len(items),
	}

	return cart, nil
}

// GetItemCount returns the total number of items in the cart
func (r *PostgresCartRepository) GetItemCount(ctx context.Context, userID string) (int, error) {
	query := `
		SELECT COALESCE(SUM(quantity), 0) as count
		FROM cart_items
		WHERE user_id = $1
	`

	var count int
	err := r.db.QueryRowContext(ctx, query, userID).Scan(&count)
	if err != nil {
		return 0, err
	}

	return count, nil
}

// AddItem adds an item to the cart
func (r *PostgresCartRepository) AddItem(ctx context.Context, userID string, item domain.CartItem) error {
	// Check if item already exists
	checkQuery := `SELECT id FROM cart_items WHERE user_id = $1 AND product_id = $2`
	var existingID string
	err := r.db.QueryRowContext(ctx, checkQuery, userID, item.ProductID).Scan(&existingID)

	if err == sql.ErrNoRows {
		// Insert new item
		insertQuery := `
			INSERT INTO cart_items (user_id, product_id, quantity, created_at, updated_at)
			VALUES ($1, $2, $3, NOW(), NOW())
			RETURNING id
		`
		return r.db.QueryRowContext(ctx, insertQuery, userID, item.ProductID, item.Quantity).Scan(&item.ID)
	} else if err != nil {
		return err
	}

	// Update existing item quantity
	updateQuery := `
		UPDATE cart_items
		SET quantity = quantity + $1, updated_at = NOW()
		WHERE id = $2
	`
	_, err = r.db.ExecContext(ctx, updateQuery, item.Quantity, existingID)
	return err
}

// UpdateItem updates the quantity of a cart item
func (r *PostgresCartRepository) UpdateItem(ctx context.Context, userID, itemID string, quantity int) error {
	query := `
		UPDATE cart_items
		SET quantity = $1, updated_at = NOW()
		WHERE id = $2 AND user_id = $3
	`

	result, err := r.db.ExecContext(ctx, query, quantity, itemID, userID)
	if err != nil {
		return err
	}

	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}

	if rows == 0 {
		return domain.ErrNotFound
	}

	return nil
}

// RemoveItem removes a single item from the cart
func (r *PostgresCartRepository) RemoveItem(ctx context.Context, userID, itemID string) error {
	query := `
		DELETE FROM cart_items
		WHERE id = $1 AND user_id = $2
	`

	result, err := r.db.ExecContext(ctx, query, itemID, userID)
	if err != nil {
		return err
	}

	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}

	if rows == 0 {
		return domain.ErrNotFound
	}

	return nil
}

// Clear removes all items from the cart
func (r *PostgresCartRepository) Clear(ctx context.Context, userID string) error {
	query := `DELETE FROM cart_items WHERE user_id = $1`
	_, err := r.db.ExecContext(ctx, query, userID)
	return err
}
