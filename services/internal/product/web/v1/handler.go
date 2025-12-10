package v1

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/duynhne/monitoring/internal/product/core/domain"
	logicv1 "github.com/duynhne/monitoring/internal/product/logic/v1"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

var productService = logicv1.NewProductService()

func ListProducts(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	products, err := productService.ListProducts(ctx)
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

