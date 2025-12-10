package v1

import (
	"context"
	"fmt"

	"github.com/duynhne/monitoring/internal/product/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type ProductService struct{}

func NewProductService() *ProductService {
	return &ProductService{}
}

func (s *ProductService) ListProducts(ctx context.Context) ([]domain.Product, error) {
	ctx, span := middleware.StartSpan(ctx, "product.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
	))
	defer span.End()

	products := []domain.Product{
		{ID: "1", Name: "Product 1", Price: 100, Description: "Description 1", Category: "Electronics"},
		{ID: "2", Name: "Product 2", Price: 200, Description: "Description 2", Category: "Books"},
		{ID: "3", Name: "Product 3", Price: 150, Description: "Description 3", Category: "Clothing"},
	}
	return products, nil
}

func (s *ProductService) GetProduct(ctx context.Context, id string) (*domain.Product, error) {
	ctx, span := middleware.StartSpan(ctx, "product.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.id", id),
	))
	defer span.End()

	// Mock logic: simulate product not found for id "999"
	if id == "999" {
		span.SetAttributes(attribute.Bool("product.found", false))
		return nil, fmt.Errorf("get product by id %q: %w", id, ErrProductNotFound)
	}

	product := &domain.Product{
		ID:          id,
		Name:        "Product " + id,
		Price:       100,
		Description: "Description for product " + id,
		Category:    "Electronics",
	}
	span.SetAttributes(attribute.Bool("product.found", true))
	return product, nil
}

func (s *ProductService) CreateProduct(ctx context.Context, req domain.CreateProductRequest) (*domain.Product, error) {
	ctx, span := middleware.StartSpan(ctx, "product.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.name", req.Name),
	))
	defer span.End()

	// Mock logic: validate price
	if req.Price <= 0 {
		span.SetAttributes(attribute.Bool("product.created", false))
		return nil, fmt.Errorf("validate price %.2f for product %q: %w", req.Price, req.Name, ErrInvalidPrice)
	}

	product := &domain.Product{
		ID:          "new-" + req.Name,
		Name:        req.Name,
		Price:       req.Price,
		Description: req.Description,
		Category:    req.Category,
	}
	span.SetAttributes(
		attribute.String("product.id", product.ID),
		attribute.Bool("product.created", true),
	)
	return product, nil
}

