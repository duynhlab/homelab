package v1

import (
	"context"

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

	product := &domain.Product{
		ID:          id,
		Name:        "Product " + id,
		Price:       100,
		Description: "Description for product " + id,
		Category:    "Electronics",
	}
	return product, nil
}

func (s *ProductService) CreateProduct(ctx context.Context, req domain.CreateProductRequest) (*domain.Product, error) {
	ctx, span := middleware.StartSpan(ctx, "product.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.name", req.Name),
	))
	defer span.End()

	product := &domain.Product{
		ID:          "new-" + req.Name,
		Name:        req.Name,
		Price:       req.Price,
		Description: req.Description,
		Category:    req.Category,
	}
	span.SetAttributes(attribute.String("product.id", product.ID))
	return product, nil
}

