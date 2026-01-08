package v1

import (
	"context"
	"errors"

	"github.com/duynhne/monitoring/services/product/internal/core/domain"
	"github.com/duynhne/monitoring/services/product/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// ProductService handles product business logic
type ProductService struct {
	productRepo domain.ProductRepository
}

// NewProductService creates a new ProductService with repository injection
func NewProductService(repo domain.ProductRepository) *ProductService {
	return &ProductService{productRepo: repo}
}

// ListProducts retrieves all products with optional filtering
func (s *ProductService) ListProducts(ctx context.Context, filters domain.ProductFilters) ([]domain.Product, error) {
	ctx, span := middleware.StartSpan(ctx, "product.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
	))
	defer span.End()

	// Call repository
	products, err := s.productRepo.FindAll(ctx, filters)
	if err != nil {
		span.RecordError(err)
		return nil, err
	}

	span.SetAttributes(attribute.Int("products.count", len(products)))
	return products, nil
}

// GetProduct retrieves a single product by ID
func (s *ProductService) GetProduct(ctx context.Context, id string) (*domain.Product, error) {
	ctx, span := middleware.StartSpan(ctx, "product.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.id", id),
	))
	defer span.End()

	// Call repository
	product, err := s.productRepo.FindByID(ctx, id)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			span.SetAttributes(attribute.Bool("product.found", false))
			return nil, ErrProductNotFound
		}
		span.RecordError(err)
		return nil, err
	}

	span.SetAttributes(attribute.Bool("product.found", true))
	return product, nil
}

// GetRelatedProducts retrieves related products for a given product
func (s *ProductService) GetRelatedProducts(ctx context.Context, productID string, limit int) ([]domain.Product, error) {
	ctx, span := middleware.StartSpan(ctx, "product.related", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.id", productID),
	))
	defer span.End()

	// Call repository
	products, err := s.productRepo.FindRelatedProducts(ctx, productID, limit)
	if err != nil {
		span.RecordError(err)
		return nil, err
	}

	return products, nil
}

// CreateProduct creates a new product
func (s *ProductService) CreateProduct(ctx context.Context, req domain.CreateProductRequest) (*domain.Product, error) {
	ctx, span := middleware.StartSpan(ctx, "product.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.name", req.Name),
	))
	defer span.End()

	// Business validation
	if req.Price <= 0 {
		span.SetAttributes(attribute.Bool("product.created", false))
		return nil, ErrInvalidPrice
	}

	// Create product domain model
	product := &domain.Product{
		Name:        req.Name,
		Description: req.Description,
		Price:       req.Price,
		Category:    req.Category,
	}

	// Call repository
	err := s.productRepo.Create(ctx, product)
	if err != nil {
		span.RecordError(err)
		return nil, err
	}

	span.SetAttributes(
		attribute.String("product.id", product.ID),
		attribute.Bool("product.created", true),
	)
	span.AddEvent("product.created")

	return product, nil
}
