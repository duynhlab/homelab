package v2

import (
	"context"
	"errors"
	"github.com/jackc/pgx/v5"
	"fmt"
	"strconv"

	database "github.com/duynhne/monitoring/services/cart/internal/core"
	"github.com/duynhne/monitoring/services/cart/internal/core/domain"
	"github.com/duynhne/monitoring/services/cart/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type CartService struct{}

func NewCartService() *CartService {
	return &CartService{}
}

func (s *CartService) GetCart(ctx context.Context, cartId string) (*domain.Cart, error) {
	ctx, span := middleware.StartSpan(ctx, "cart.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("cart.id", cartId),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Convert cartId to user_id (in production, validate cartId belongs to user)
	userID, err := strconv.Atoi(cartId)
	if err != nil {
		span.SetAttributes(attribute.Bool("cart.found", false))
		return nil, fmt.Errorf("invalid cart id %q: %w", cartId, ErrCartNotFound)
	}

	// Query cart items
	query := `SELECT id, user_id, product_id, quantity FROM cart_items WHERE user_id = $1`
	rows, err := db.Query(ctx, query, userID)
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
		price := 100.0

		item := domain.CartItem{
			ID:           strconv.Itoa(itemID),
			ProductID:    strconv.Itoa(productID),
			ProductPrice: price,
			Quantity:     quantity,
			Subtotal:     price * float64(quantity),
		}
		items = append(items, item)
		total += price * float64(quantity)
	}

	if err = rows.Err(); err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("scan cart items: %w", err)
	}

	cart := &domain.Cart{
		UserID:    strconv.Itoa(userID),
		Items:     items,
		Subtotal:  total,
		Shipping:  5.00,
		Total:     total + 5.00,
		ItemCount: len(items),
	}

	span.SetAttributes(attribute.Int("items.count", len(items)))
	return cart, nil
}

func (s *CartService) AddItem(ctx context.Context, cartId string, req domain.AddToCartRequest) (*domain.CartItem, error) {
	ctx, span := middleware.StartSpan(ctx, "cart.add", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("cart.id", cartId),
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
		return nil, fmt.Errorf("add product %q to cart %q with quantity %d: %w", req.ProductID, cartId, req.Quantity, ErrInvalidQuantity)
	}

	// Convert IDs
	userID, err := strconv.Atoi(cartId)
	if err != nil {
		return nil, fmt.Errorf("invalid cart id %q: %w", cartId, ErrCartNotFound)
	}
	productID, err := strconv.Atoi(req.ProductID)
	if err != nil {
		return nil, fmt.Errorf("invalid product id %q: %w", req.ProductID, ErrInvalidQuantity)
	}

	// Check if item exists
	var existingID int
	var existingQuantity int
	checkQuery := `SELECT id, quantity FROM cart_items WHERE user_id = $1 AND product_id = $2`
	err = db.QueryRow(ctx, checkQuery, userID, productID).Scan(&existingID, &existingQuantity)
	if err == nil {
		// Update quantity
		newQuantity := existingQuantity + req.Quantity
		updateQuery := `UPDATE cart_items SET quantity = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`
		_, err = db.Exec(ctx, updateQuery, newQuantity, existingID)
		if err != nil {
			span.RecordError(err)
			return nil, fmt.Errorf("update cart item: %w", err)
		}
		item := &domain.CartItem{
			ProductID:    req.ProductID,
			ProductPrice: 100.0,
			Quantity:     newQuantity,
			Subtotal:     100.0 * float64(newQuantity),
		}
		span.SetAttributes(attribute.Bool("item.added", true))
		return item, nil
	} else if !errors.Is(err, pgx.ErrNoRows) {
		span.RecordError(err)
		return nil, fmt.Errorf("check existing cart item: %w", err)
	}

	// Insert new item
	insertQuery := `INSERT INTO cart_items (user_id, product_id, quantity) VALUES ($1, $2, $3) RETURNING id`
	var itemID int
	err = db.QueryRow(ctx, insertQuery, userID, productID, req.Quantity).Scan(&itemID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("insert cart item: %w", err)
	}

	item := &domain.CartItem{
		ProductID:    req.ProductID,
		ProductPrice: 100.0,
		Quantity:     req.Quantity,
		Subtotal:     100.0 * float64(req.Quantity),
	}

	span.SetAttributes(attribute.Bool("item.added", true))
	span.AddEvent("cart.item.added.v2")

	return item, nil
}
