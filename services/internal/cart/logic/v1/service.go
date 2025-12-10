package v1

import (
	"context"
	"fmt"

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

	cart := &domain.Cart{
		ID: "cart-1",
		Items: []domain.CartItem{
			{ProductID: "1", Quantity: 2, Price: 100},
			{ProductID: "2", Quantity: 1, Price: 200},
		},
		Total: 400,
	}
	return cart, nil
}

func (s *CartService) AddToCart(ctx context.Context, req domain.AddToCartRequest) (*domain.CartItem, error) {
	ctx, span := middleware.StartSpan(ctx, "cart.add", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.id", req.ProductID),
	))
	defer span.End()

	// Mock logic: validate quantity
	if req.Quantity <= 0 {
		span.SetAttributes(attribute.Bool("item.added", false))
		return nil, fmt.Errorf("add product %q to cart with quantity %d: %w", req.ProductID, req.Quantity, ErrInvalidQuantity)
	}

	item := &domain.CartItem{
		ProductID: req.ProductID,
		Quantity:  req.Quantity,
		Price:     100,
	}
	span.SetAttributes(attribute.Bool("item.added", true))
	return item, nil
}

