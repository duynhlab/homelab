package v2

import (
	"errors"
	"net/http"

	"github.com/duynhne/monitoring/services/cart/internal/core/domain"
	logicv2 "github.com/duynhne/monitoring/services/cart/internal/logic/v2"
	"github.com/duynhne/monitoring/services/cart/middleware"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

var cartService = logicv2.NewCartService()

func GetCart(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)
	cartId := c.Param("cartId")
	span.SetAttributes(attribute.String("cart.id", cartId))

	cart, err := cartService.GetCart(ctx, cartId)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to get cart", zap.Error(err), zap.String("cart_id", cartId))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Cart retrieved", zap.String("cart_id", cartId))
	c.JSON(http.StatusOK, cart)
}

func AddItem(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)
	cartId := c.Param("cartId")
	span.SetAttributes(attribute.String("cart.id", cartId))

	var req domain.AddToCartRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		span.SetAttributes(attribute.Bool("request.valid", false))
		span.RecordError(err)
		zapLogger.Error("Invalid request", zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	span.SetAttributes(attribute.Bool("request.valid", true))
	item, err := cartService.AddItem(ctx, cartId, req)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to add item", zap.Error(err))

		switch {
		case errors.Is(err, logicv2.ErrInvalidQuantity):
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid quantity"})
		case errors.Is(err, logicv2.ErrCartNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "Cart not found"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Item added to cart", zap.String("cart_id", cartId), zap.String("product_id", item.ProductID))
	c.JSON(http.StatusCreated, gin.H{
		"cartId": cartId,
		"item":   item,
	})
}
