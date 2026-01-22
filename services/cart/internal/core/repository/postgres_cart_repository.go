package repository

import (
	"context"
	"errors"

	"github.com/duynhne/monitoring/services/cart/internal/core/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresCartRepository implements CartRepository using PostgreSQL with pgx
type PostgresCartRepository struct {
	pool *pgxpool.Pool
}

// NewPostgresCartRepository creates a new PostgreSQL cart repository
func NewPostgresCartRepository(pool *pgxpool.Pool) *PostgresCartRepository {
	return &PostgresCartRepository{pool: pool}
}

// FindByUserID retrieves a cart by user ID
func (r *PostgresCartRepository) FindByUserID(ctx context.Context, userID string) (*domain.Cart, error) {
	query := `
		SELECT id, product_id, product_name, product_price, quantity
		FROM cart_items
		WHERE user_id = $1
	`

	rows, err := r.pool.Query(ctx, query, userID)
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
		Shipping:  5.00,
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
	err := r.pool.QueryRow(ctx, query, userID).Scan(&count)
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
	err := r.pool.QueryRow(ctx, checkQuery, userID, item.ProductID).Scan(&existingID)

	if errors.Is(err, pgx.ErrNoRows) {
		// Insert new item with denormalized product details
		insertQuery := `
			INSERT INTO cart_items (user_id, product_id, product_name, product_price, quantity, created_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
			RETURNING id
		`
		return r.pool.QueryRow(ctx, insertQuery, userID, item.ProductID, item.ProductName, item.ProductPrice, item.Quantity).Scan(&item.ID)
	} else if err != nil {
		return err
	}

	// Update existing item quantity
	updateQuery := `
		UPDATE cart_items
		SET quantity = quantity + $1, updated_at = NOW()
		WHERE id = $2
	`
	_, err = r.pool.Exec(ctx, updateQuery, item.Quantity, existingID)
	return err
}

// UpdateItem updates the quantity of a cart item
func (r *PostgresCartRepository) UpdateItem(ctx context.Context, userID, itemID string, quantity int) error {
	query := `
		UPDATE cart_items
		SET quantity = $1, updated_at = NOW()
		WHERE id = $2 AND user_id = $3
	`

	result, err := r.pool.Exec(ctx, query, quantity, itemID, userID)
	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
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

	result, err := r.pool.Exec(ctx, query, itemID, userID)
	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}

// Clear removes all items from the cart
func (r *PostgresCartRepository) Clear(ctx context.Context, userID string) error {
	query := `DELETE FROM cart_items WHERE user_id = $1`
	_, err := r.pool.Exec(ctx, query, userID)
	return err
}
