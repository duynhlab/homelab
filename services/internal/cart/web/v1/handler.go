package v1

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/duynhne/monitoring/internal/cart/core/domain"
	logicv1 "github.com/duynhne/monitoring/internal/cart/logic/v1"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

var cartService = logicv1.NewCartService()

func GetCart(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	cart, err := cartService.GetCart(ctx)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to get cart", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Cart retrieved")
	c.JSON(http.StatusOK, cart)
}

func AddToCart(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	var req domain.AddToCartRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		span.SetAttributes(attribute.Bool("request.valid", false))
		span.RecordError(err)
		zapLogger.Error("Invalid request", zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	span.SetAttributes(attribute.Bool("request.valid", true))
	item, err := cartService.AddToCart(ctx, req)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to add to cart", zap.Error(err))
		
		switch {
		case errors.Is(err, logicv1.ErrInvalidQuantity):
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid quantity"})
		case errors.Is(err, logicv1.ErrCartNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "Cart not found"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Item added to cart", zap.String("product_id", item.ProductID))
	c.JSON(http.StatusCreated, item)
}

