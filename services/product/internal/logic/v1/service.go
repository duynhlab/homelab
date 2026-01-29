package v1

import (
	"context"
	"errors"

	"github.com/duynhne/monitoring/services/product/internal/core/cache"
	"github.com/duynhne/monitoring/services/product/internal/core/domain"
	"github.com/duynhne/monitoring/services/product/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// ProductService handles product business logic
type ProductService struct {
	productRepo domain.ProductRepository
	productCache *cache.ProductCache // Optional - nil if caching disabled
}

// NewProductService creates a new ProductService with repository injection
// productCache can be nil if caching is disabled
func NewProductService(repo domain.ProductRepository, productCache *cache.ProductCache) *ProductService {
	return &ProductService{
		productRepo: repo,
		productCache: productCache,
	}
}

// ListProducts retrieves all products with optional filtering
// Implements Cache-Aside pattern: check cache first, fallback to repository
func (s *ProductService) ListProducts(ctx context.Context, filters domain.ProductFilters) ([]domain.Product, int, error) {
	ctx, span := middleware.StartSpan(ctx, "product.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
	))
	defer span.End()

	// Cache-Aside pattern: Check cache first
	if s.productCache != nil {
		cachedProducts, cachedTotal, err := s.productCache.GetProductList(ctx, filters)
		if err != nil {
			// Cache error - log but continue to database
			span.RecordError(err)
			span.SetAttributes(attribute.Bool("cache.error", true))
		} else if cachedProducts != nil {
			// Cache hit
			span.SetAttributes(
				attribute.Bool("cache.hit", true),
				attribute.Int("products.count", len(cachedProducts)),
				attribute.Int("products.total", cachedTotal),
			)
			return cachedProducts, cachedTotal, nil
		}
		// Cache miss - continue to database
		span.SetAttributes(attribute.Bool("cache.hit", false))
	}

	// Cache miss or cache disabled - query repository
	products, err := s.productRepo.FindAll(ctx, filters)
	if err != nil {
		span.RecordError(err)
		return nil, 0, err
	}

	// Get total count
	total, err := s.productRepo.Count(ctx, filters)
	if err != nil {
		span.RecordError(err)
		return nil, 0, err
	}

	// Write to cache (async - don't block on cache write errors)
	if s.productCache != nil {
		if err := s.productCache.SetProductList(ctx, filters, products, total); err != nil {
			// Log cache write error but don't fail the request
			span.RecordError(err)
			span.SetAttributes(attribute.Bool("cache.write_error", true))
		}
	}

	span.SetAttributes(
		attribute.Int("products.count", len(products)),
		attribute.Int("products.total", total),
	)
	return products, total, nil
}

// GetProduct retrieves a single product by ID
// Implements Cache-Aside pattern: check cache first, fallback to repository
func (s *ProductService) GetProduct(ctx context.Context, id string) (*domain.Product, error) {
	ctx, span := middleware.StartSpan(ctx, "product.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.id", id),
	))
	defer span.End()

	// Cache-Aside pattern: Check cache first
	if s.productCache != nil {
		cachedProduct, err := s.productCache.GetProduct(ctx, id)
		if err != nil {
			// Cache error - log but continue to database
			span.RecordError(err)
			span.SetAttributes(attribute.Bool("cache.error", true))
		} else if cachedProduct != nil {
			// Cache hit
			span.SetAttributes(attribute.Bool("cache.hit", true))
			span.SetAttributes(attribute.Bool("product.found", true))
			return cachedProduct, nil
		}
		// Cache miss - continue to database
		span.SetAttributes(attribute.Bool("cache.hit", false))
	}

	// Cache miss or cache disabled - query repository
	product, err := s.productRepo.FindByID(ctx, id)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			span.SetAttributes(attribute.Bool("product.found", false))
			return nil, ErrProductNotFound
		}
		span.RecordError(err)
		return nil, err
	}

	// Write to cache (async - don't block on cache write errors)
	if s.productCache != nil {
		if err := s.productCache.SetProduct(ctx, id, product); err != nil {
			// Log cache write error but don't fail the request
			span.RecordError(err)
			span.SetAttributes(attribute.Bool("cache.write_error", true))
		}
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

	// Invalidate cache after successful creation
	// This ensures new products appear in list queries
	if s.productCache != nil {
		// Invalidate list caches (new product should appear in lists)
		if err := s.productCache.InvalidateProductList(ctx); err != nil {
			// Log cache invalidation error but don't fail the request
			span.RecordError(err)
			span.SetAttributes(attribute.Bool("cache.invalidation_error", true))
		}
	}

	span.SetAttributes(
		attribute.String("product.id", product.ID),
		attribute.Bool("product.created", true),
	)
	span.AddEvent("product.created")

	return product, nil
}
