package v1

import (
	"errors"
	"net/http"

	"github.com/duynhne/monitoring/services/product/internal/core/domain"
	logicv1 "github.com/duynhne/monitoring/services/product/internal/logic/v1"
	"github.com/duynhne/monitoring/services/product/middleware"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

// productService will be initialized in main.go with repository injection
var productService *logicv1.ProductService

// SetProductService sets the product service instance
func SetProductService(service *logicv1.ProductService) {
	productService = service
}

func ListProducts(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	// Get query parameters for filtering
	filters := domain.ProductFilters{
		Category: c.Query("category"),
		Search:   c.Query("search"),
		SortBy:   c.Query("sort"),
		Order:    c.Query("order"),
	}

	products, err := productService.ListProducts(ctx, filters)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to list products", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Products listed", zap.Int("count", len(products)))
	c.JSON(http.StatusOK, products)
}

func GetProduct(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)
	id := c.Param("id")
	span.SetAttributes(attribute.String("product.id", id))

	product, err := productService.GetProduct(ctx, id)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to get product", zap.Error(err))

		switch {
		case errors.Is(err, logicv1.ErrProductNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Product retrieved", zap.String("product_id", id))
	c.JSON(http.StatusOK, product)
}

func CreateProduct(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	var req domain.CreateProductRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		span.SetAttributes(attribute.Bool("request.valid", false))
		span.RecordError(err)
		zapLogger.Error("Invalid request", zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	span.SetAttributes(attribute.Bool("request.valid", true))
	product, err := productService.CreateProduct(ctx, req)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to create product", zap.Error(err))

		switch {
		case errors.Is(err, logicv1.ErrInvalidPrice):
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid price"})
		case errors.Is(err, logicv1.ErrInsufficientStock):
			c.JSON(http.StatusBadRequest, gin.H{"error": "Insufficient stock"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Product created", zap.String("product_id", product.ID))
	c.JSON(http.StatusCreated, product)
}

// GetProductDetails retrieves aggregated product details (product + reviews + stock + related)
func GetProductDetails(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)
	id := c.Param("id")
	span.SetAttributes(attribute.String("product.id", id))

	// Get product details
	product, err := productService.GetProduct(ctx, id)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to get product", zap.Error(err))

		switch {
		case errors.Is(err, logicv1.ErrProductNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	// Get related products (aggregation in Web layer)
	relatedProducts, _ := productService.GetRelatedProducts(ctx, id, 4)

	// TODO: Get reviews from review service when available
	// reviews, _ := reviewService.GetProductReviews(ctx, id)

	// TODO: Get stock from inventory service when available
	// stock, _ := inventoryService.GetStock(ctx, id)

	// Aggregate response
	response := gin.H{
		"product": product,
		"stock": gin.H{
			"available": true, // Mock data
			"quantity":  50,   // Mock data
		},
		"reviews": []gin.H{}, // Empty for now, will be populated when review service is integrated
		"reviews_summary": gin.H{
			"total":          0,
			"average_rating": 0.0,
		},
		"related_products": relatedProducts,
	}

	zapLogger.Info("Product details retrieved", zap.String("product_id", id))
	c.JSON(http.StatusOK, response)
}
