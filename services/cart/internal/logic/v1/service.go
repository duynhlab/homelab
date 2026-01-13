package v1

import (
	"context"
	"errors"

	"github.com/duynhne/monitoring/services/cart/internal/core/domain"
	"github.com/duynhne/monitoring/services/cart/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// CartService handles cart business logic
type CartService struct {
	cartRepo domain.CartRepository
}

// NewCartService creates a new CartService with repository injection
func NewCartService(repo domain.CartRepository) *CartService {
	return &CartService{cartRepo: repo}
}

// GetCart retrieves the cart for a user
func (s *CartService) GetCart(ctx context.Context, userID string) (*domain.Cart, error) {
	ctx, span := middleware.StartSpan(ctx, "cart.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("user.id", userID),
	))
	defer span.End()

	// Call repository
	cart, err := s.cartRepo.FindByUserID(ctx, userID)
	if err != nil {
		span.RecordError(err)
		return nil, err
	}

	span.SetAttributes(attribute.Int("items.count", len(cart.Items)))
	return cart, nil
}

// GetCartCount returns the total number of items in the cart
func (s *CartService) GetCartCount(ctx context.Context, userID string) (int, error) {
	ctx, span := middleware.StartSpan(ctx, "cart.count", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("user.id", userID),
	))
	defer span.End()

	// Call repository
	count, err := s.cartRepo.GetItemCount(ctx, userID)
	if err != nil {
		span.RecordError(err)
		return 0, err
	}

	span.SetAttributes(attribute.Int("cart.count", count))
	return count, nil
}

// AddToCart adds an item to the cart
func (s *CartService) AddToCart(ctx context.Context, userID string, req domain.AddToCartRequest) (*domain.CartItem, error) {
	ctx, span := middleware.StartSpan(ctx, "cart.add", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.id", req.ProductID),
	))
	defer span.End()

	// Business validation
	if req.Quantity <= 0 {
		span.SetAttributes(attribute.Bool("item.added", false))
		return nil, ErrInvalidQuantity
	}

	// Create cart item
	item := domain.CartItem{
		ProductID: req.ProductID,
		Quantity:  req.Quantity,
	}

	// Call repository
	err := s.cartRepo.AddItem(ctx, userID, item)
	if err != nil {
		span.RecordError(err)
		return nil, err
	}

	span.SetAttributes(attribute.Bool("item.added", true))
	span.AddEvent("cart.item.added")

	return &item, nil
}

// UpdateItemQuantity updates the quantity of a cart item
func (s *CartService) UpdateItemQuantity(ctx context.Context, userID, itemID string, quantity int) error {
	ctx, span := middleware.StartSpan(ctx, "cart.update", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("item.id", itemID),
	))
	defer span.End()

	// Business validation
	if quantity <= 0 {
		span.SetAttributes(attribute.Bool("item.updated", false))
		return ErrInvalidQuantity
	}

	// Call repository
	err := s.cartRepo.UpdateItem(ctx, userID, itemID, quantity)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			return ErrCartItemNotFound
		}
		span.RecordError(err)
		return err
	}

	span.SetAttributes(attribute.Bool("item.updated", true))
	return nil
}

// RemoveItem removes a single item from the cart
func (s *CartService) RemoveItem(ctx context.Context, userID, itemID string) error {
	ctx, span := middleware.StartSpan(ctx, "cart.remove", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("item.id", itemID),
	))
	defer span.End()

	// Call repository
	err := s.cartRepo.RemoveItem(ctx, userID, itemID)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			return ErrCartItemNotFound
		}
		span.RecordError(err)
		return err
	}

	span.SetAttributes(attribute.Bool("item.removed", true))
	span.AddEvent("cart.item.removed")
	return nil
}

// ClearCart removes all items from the cart
func (s *CartService) ClearCart(ctx context.Context, userID string) error {
	ctx, span := middleware.StartSpan(ctx, "cart.clear", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("user.id", userID),
	))
	defer span.End()

	// Call repository
	err := s.cartRepo.Clear(ctx, userID)
	if err != nil {
		span.RecordError(err)
		return err
	}

	span.SetAttributes(attribute.Bool("cart.cleared", true))
	span.AddEvent("cart.cleared")
	return nil
}
