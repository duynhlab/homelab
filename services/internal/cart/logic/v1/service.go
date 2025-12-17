package v1

import (
	"context"
	"database/sql"
	"fmt"
	"strconv"

	"github.com/duynhne/monitoring/internal/cart/core/database"
	"github.com/duynhne/monitoring/internal/cart/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type CartService struct{}

func NewCartService() *CartService {
	return &CartService{}
}

func (s *CartService) GetCart(ctx context.Context) (*domain.Cart, error) {
	ctx, span := middleware.StartSpan(ctx, "cart.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// TODO: Extract user_id from JWT token or session context
	// For now, use user_id = 1 as default
	userID := 1

	// Query cart items
	query := `SELECT id, user_id, product_id, quantity FROM cart_items WHERE user_id = $1`
	rows, err := db.QueryContext(ctx, query, userID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("query cart items: %w", err)
	}
	defer rows.Close()

	var items []domain.CartItem
	var total float64

	for rows.Next() {
		var itemID, productID int
		var quantity int

		err := rows.Scan(&itemID, &userID, &productID, &quantity)
		if err != nil {
			span.RecordError(err)
			continue
		}

		// TODO: Fetch product price from product service
		// For now, use mock price
		price := 100.0

		item := domain.CartItem{
			ProductID: strconv.Itoa(productID),
			Quantity:  quantity,
			Price:     price,
		}
		items = append(items, item)
		total += price * float64(quantity)
	}

	if err = rows.Err(); err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("scan cart items: %w", err)
	}

	cart := &domain.Cart{
		ID:    strconv.Itoa(userID),
		Items: items,
		Total: total,
	}

	span.SetAttributes(attribute.Int("items.count", len(items)))
	return cart, nil
}

func (s *CartService) AddToCart(ctx context.Context, req domain.AddToCartRequest) (*domain.CartItem, error) {
	ctx, span := middleware.StartSpan(ctx, "cart.add", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.id", req.ProductID),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Validate quantity
	if req.Quantity <= 0 {
		span.SetAttributes(attribute.Bool("item.added", false))
		return nil, fmt.Errorf("add product %q to cart with quantity %d: %w", req.ProductID, req.Quantity, ErrInvalidQuantity)
	}

	// Convert product ID to int
	productID, err := strconv.Atoi(req.ProductID)
	if err != nil {
		span.SetAttributes(attribute.Bool("item.added", false))
		return nil, fmt.Errorf("invalid product id %q: %w", req.ProductID, ErrInvalidQuantity)
	}

	// TODO: Extract user_id from JWT token or session context
	userID := 1

	// Check if item already exists in cart
	var existingID int
	var existingQuantity int
	checkQuery := `SELECT id, quantity FROM cart_items WHERE user_id = $1 AND product_id = $2`
	err = db.QueryRowContext(ctx, checkQuery, userID, productID).Scan(&existingID, &existingQuantity)
	if err == nil {
		// Update quantity
		newQuantity := existingQuantity + req.Quantity
		updateQuery := `UPDATE cart_items SET quantity = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`
		_, err = db.ExecContext(ctx, updateQuery, newQuantity, existingID)
		if err != nil {
			span.RecordError(err)
			return nil, fmt.Errorf("update cart item: %w", err)
		}
		// TODO: Fetch product price from product service
		item := &domain.CartItem{
			ProductID: req.ProductID,
			Quantity:  newQuantity,
			Price:     100.0,
		}
		span.SetAttributes(attribute.Bool("item.added", true))
		return item, nil
	} else if err != sql.ErrNoRows {
		span.RecordError(err)
		return nil, fmt.Errorf("check existing cart item: %w", err)
	}

	// Insert new cart item
	insertQuery := `INSERT INTO cart_items (user_id, product_id, quantity) VALUES ($1, $2, $3) RETURNING id`
	var itemID int
	err = db.QueryRowContext(ctx, insertQuery, userID, productID, req.Quantity).Scan(&itemID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("insert cart item: %w", err)
	}

	// TODO: Fetch product price from product service
	item := &domain.CartItem{
		ProductID: req.ProductID,
		Quantity:  req.Quantity,
		Price:     100.0,
	}

	span.SetAttributes(attribute.Bool("item.added", true))
	span.AddEvent("cart.item.added")

	return item, nil
}

