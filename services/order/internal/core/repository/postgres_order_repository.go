package repository

import (
	"context"
	"database/sql"
	"errors"
	"strconv"
	"time"

	"github.com/duynhne/monitoring/services/order/internal/core/domain"
)

// PostgresOrderRepository implements OrderRepository using PostgreSQL
type PostgresOrderRepository struct {
	db *sql.DB
}

// NewPostgresOrderRepository creates a new PostgreSQL order repository
func NewPostgresOrderRepository(db *sql.DB) *PostgresOrderRepository {
	return &PostgresOrderRepository{db: db}
}

// FindByID retrieves an order by ID
func (r *PostgresOrderRepository) FindByID(ctx context.Context, id string) (*domain.Order, error) {
	query := `
		SELECT id, user_id, status, subtotal, shipping, total, created_at
		FROM orders
		WHERE id = $1
	`

	var order domain.Order
	var idInt int
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&idInt,
		&order.UserID,
		&order.Status,
		&order.Subtotal,
		&order.Shipping,
		&order.Total,
		&order.CreatedAt,
	)

	if err == sql.ErrNoRows {
		return nil, domain.ErrNotFound
	}
	if err != nil {
		return nil, err
	}

	order.ID = strconv.Itoa(idInt)

	// Get order items
	itemsQuery := `
		SELECT product_id, product_name, quantity, price, subtotal
		FROM order_items
		WHERE order_id = $1
	`

	rows, err := r.db.QueryContext(ctx, itemsQuery, idInt)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var item domain.OrderItem
		err := rows.Scan(&item.ProductID, &item.ProductName, &item.Quantity, &item.Price, &item.Subtotal)
		if err != nil {
			continue
		}
		order.Items = append(order.Items, item)
	}

	return &order, nil
}

// FindByUserID retrieves all orders for a user
func (r *PostgresOrderRepository) FindByUserID(ctx context.Context, userID string) ([]domain.Order, error) {
	query := `
		SELECT id, user_id, status, subtotal, shipping, total, created_at
		FROM orders
		WHERE user_id = $1
		ORDER BY created_at DESC
	`

	rows, err := r.db.QueryContext(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var orders []domain.Order
	for rows.Next() {
		var order domain.Order
		var idInt int
		err := rows.Scan(&idInt, &order.UserID, &order.Status, &order.Subtotal, &order.Shipping, &order.Total, &order.CreatedAt)
		if err != nil {
			continue
		}
		order.ID = strconv.Itoa(idInt)
		orders = append(orders, order)
	}

	return orders, nil
}

// Create creates a new order
func (r *PostgresOrderRepository) Create(ctx context.Context, order *domain.Order) error {
	query := `
		INSERT INTO orders (user_id, status, subtotal, shipping, total, created_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id
	`

	var id int
	err := r.db.QueryRowContext(ctx, query,
		order.UserID,
		order.Status,
		order.Subtotal,
		order.Shipping,
		order.Total,
		time.Now(),
	).Scan(&id)

	if err != nil {
		return err
	}

	order.ID = strconv.Itoa(id)

	// Insert order items
	for _, item := range order.Items {
		itemQuery := `
			INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
			VALUES ($1, $2, $3, $4, $5, $6)
		`
		_, err := r.db.ExecContext(ctx, itemQuery, id, item.ProductID, item.ProductName, item.Quantity, item.Price, item.Subtotal)
		if err != nil {
			return err
		}
	}

	return nil
}

// CreateWithTx creates a new order within a transaction
func (r *PostgresOrderRepository) CreateWithTx(ctx context.Context, tx domain.Transaction, order *domain.Order) error {
	sqlTx, ok := tx.(*PostgresTransaction)
	if !ok {
		return errors.New("invalid transaction type")
	}

	query := `
		INSERT INTO orders (user_id, status, subtotal, shipping, total, created_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id
	`

	var id int
	err := sqlTx.tx.QueryRowContext(ctx, query,
		order.UserID,
		order.Status,
		order.Subtotal,
		order.Shipping,
		order.Total,
		time.Now(),
	).Scan(&id)

	if err != nil {
		return err
	}

	order.ID = strconv.Itoa(id)

	// Insert order items
	for _, item := range order.Items {
		itemQuery := `
			INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
			VALUES ($1, $2, $3, $4, $5, $6)
		`
		_, err := sqlTx.tx.ExecContext(ctx, itemQuery, id, item.ProductID, item.ProductName, item.Quantity, item.Price, item.Subtotal)
		if err != nil {
			return err
		}
	}

	return nil
}

// UpdateStatus updates the status of an order
func (r *PostgresOrderRepository) UpdateStatus(ctx context.Context, id, status string) error {
	query := `
		UPDATE orders
		SET status = $1, updated_at = NOW()
		WHERE id = $2
	`

	result, err := r.db.ExecContext(ctx, query, status, id)
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
