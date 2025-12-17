package v2

import (
	"context"
	"database/sql"
	"fmt"
	"strconv"

	"github.com/duynhne/monitoring/internal/order/core/database"
	"github.com/duynhne/monitoring/internal/order/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type OrderService struct{}

func NewOrderService() *OrderService {
	return &OrderService{}
}

func (s *OrderService) ListOrders(ctx context.Context) ([]domain.Order, error) {
	ctx, span := middleware.StartSpan(ctx, "order.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// TODO: Extract user_id from JWT token or session context
	userID := 1

	// Query orders
	query := `SELECT id, user_id, total_amount, status FROM orders WHERE user_id = $1 ORDER BY created_at DESC`
	rows, err := db.QueryContext(ctx, query, userID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("query orders: %w", err)
	}
	defer rows.Close()

	var orders []domain.Order
	for rows.Next() {
		var orderID int
		var totalAmount float64
		var status string

		err := rows.Scan(&orderID, &userID, &totalAmount, &status)
		if err != nil {
			span.RecordError(err)
			continue
		}

		// Query order items
		itemsQuery := `SELECT product_id, quantity, price FROM order_items WHERE order_id = $1`
		itemRows, err := db.QueryContext(ctx, itemsQuery, orderID)
		if err != nil {
			span.RecordError(err)
			continue
		}

		var items []domain.OrderItem
		for itemRows.Next() {
			var productID int
			var quantity int
			var price float64

			err := itemRows.Scan(&productID, &quantity, &price)
			if err != nil {
				continue
			}

			items = append(items, domain.OrderItem{
				ProductID: strconv.Itoa(productID),
				Quantity:  quantity,
				Price:     price,
			})
		}
		itemRows.Close()

		orders = append(orders, domain.Order{
			ID:     strconv.Itoa(orderID),
			Status: status,
			Items:  items,
			Total:  totalAmount,
		})
	}

	if err = rows.Err(); err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("scan orders: %w", err)
	}

	span.SetAttributes(attribute.Int("orders.count", len(orders)))
	return orders, nil
}

func (s *OrderService) GetOrderStatus(ctx context.Context, orderId string) (map[string]interface{}, error) {
	ctx, span := middleware.StartSpan(ctx, "order.status", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("order.id", orderId),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Convert string ID to int
	orderID, err := strconv.Atoi(orderId)
	if err != nil {
		span.SetAttributes(attribute.Bool("order.found", false))
		return nil, fmt.Errorf("invalid order id %q: %w", orderId, ErrOrderNotFound)
	}

	// Query order status
	query := `SELECT id, status FROM orders WHERE id = $1`
	var status string

	err = db.QueryRowContext(ctx, query, orderID).Scan(&orderID, &status)
	if err != nil {
		if err == sql.ErrNoRows {
			span.SetAttributes(attribute.Bool("order.found", false))
			return nil, fmt.Errorf("get order status for id %q: %w", orderId, ErrOrderNotFound)
		}
		span.RecordError(err)
		return nil, fmt.Errorf("query order: %w", err)
	}

	// TODO: Fetch tracking number from shipping service
	statusMap := map[string]interface{}{
		"orderId":  orderId,
		"status":   status,
		"tracking": "TRK" + strconv.Itoa(orderID), // Mock tracking
	}

	span.SetAttributes(attribute.Bool("order.found", true))
	return statusMap, nil
}

func (s *OrderService) CreateOrder(ctx context.Context, req domain.CreateOrderRequest) (*domain.Order, error) {
	ctx, span := middleware.StartSpan(ctx, "order.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// TODO: Extract user_id from JWT token or session context
	userID := 1

	// Calculate total
	var totalAmount float64
	for _, item := range req.Items {
		totalAmount += item.Price * float64(item.Quantity)
	}

	// Start transaction
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Insert order
	insertOrderQuery := `INSERT INTO orders (user_id, total_amount, status) VALUES ($1, $2, $3) RETURNING id`
	var orderID int
	err = tx.QueryRowContext(ctx, insertOrderQuery, userID, totalAmount, "pending").Scan(&orderID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("insert order: %w", err)
	}

	// Insert order items
	for _, item := range req.Items {
		productID, err := strconv.Atoi(item.ProductID)
		if err != nil {
			span.RecordError(err)
			continue
		}

		insertItemQuery := `INSERT INTO order_items (order_id, product_id, quantity, price) VALUES ($1, $2, $3, $4)`
		_, err = tx.ExecContext(ctx, insertItemQuery, orderID, productID, item.Quantity, item.Price)
		if err != nil {
			span.RecordError(err)
			return nil, fmt.Errorf("insert order item: %w", err)
		}
	}

	// Commit transaction
	err = tx.Commit()
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("commit transaction: %w", err)
	}

	order := &domain.Order{
		ID:     strconv.Itoa(orderID),
		Status: "pending",
		Items:  req.Items,
		Total:  totalAmount,
	}

	span.SetAttributes(
		attribute.String("order.id", order.ID),
		attribute.Bool("order.created", true),
	)
	span.AddEvent("order.created.v2")

	return order, nil
}

