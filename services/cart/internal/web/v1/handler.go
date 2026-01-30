package v1

import (
	"errors"
	"net/http"

	"github.com/duynhne/monitoring/services/pkg/logger/clog"
	"github.com/duynhne/monitoring/services/cart/internal/core/domain"
	logicv1 "github.com/duynhne/monitoring/services/cart/internal/logic/v1"
	"github.com/duynhne/monitoring/services/cart/middleware"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// CartHandler holds the cart service dependency
type CartHandler struct {
	cartService *logicv1.CartService
}

// NewCartHandler creates a new cart handler with dependency injection
func NewCartHandler(cartService *logicv1.CartService) *CartHandler {
	return &CartHandler{cartService: cartService}
}

func (h *CartHandler) GetCart(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	// Get userID from context/auth (for now, use a placeholder)
	userID := c.GetString("user_id")
	if userID == "" {
		userID = "1" // Default for demo
	}

	cart, err := h.cartService.GetCart(ctx, userID)
	if err != nil {
		span.RecordError(err)
		clog.ErrorContext(ctx, "Failed to get cart", "error", err)

		switch {
		case errors.Is(err, logicv1.ErrCartNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "Cart not found"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	clog.InfoContext(ctx, "Cart retrieved", "user_id", userID)
	c.JSON(http.StatusOK, cart)
}

func (h *CartHandler) AddToCart(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	// Get userID from context/auth
	userID := c.GetString("user_id")
	if userID == "" {
		userID = "1" // Default for demo
	}

	var req domain.AddToCartRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		span.SetAttributes(attribute.Bool("request.valid", false))
		span.RecordError(err)
		clog.ErrorContext(ctx, "Invalid request", "error", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	span.SetAttributes(attribute.Bool("request.valid", true))
	_, err := h.cartService.AddToCart(ctx, userID, req)
	if err != nil {
		span.RecordError(err)
		clog.ErrorContext(ctx, "Failed to add to cart", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	clog.InfoContext(ctx, "Item added to cart", "user_id", userID, "product_id", req.ProductID)
	c.JSON(http.StatusOK, gin.H{"message": "Item added to cart"})
}

func (h *CartHandler) GetCartCount(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	userID := c.GetString("user_id")
	if userID == "" {
		userID = "1"
	}

	count, err := h.cartService.GetCartCount(ctx, userID)
	if err != nil {
		span.RecordError(err)
		clog.ErrorContext(ctx, "Failed to get cart count", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"count": count})
}

func (h *CartHandler) UpdateCartItem(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	userID := c.GetString("user_id")
	if userID == "" {
		userID = "1"
	}

	itemID := c.Param("itemId")

	var req struct {
		Quantity int `json:"quantity" binding:"required,min=1"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		span.RecordError(err)
		clog.ErrorContext(ctx, "Invalid request", "error", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err := h.cartService.UpdateItemQuantity(ctx, userID, itemID, req.Quantity)
	if err != nil {
		span.RecordError(err)
		clog.ErrorContext(ctx, "Failed to update cart item", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Cart item updated"})
}

func (h *CartHandler) RemoveCartItem(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	userID := c.GetString("user_id")
	if userID == "" {
		userID = "1"
	}

	itemID := c.Param("itemId")

	err := h.cartService.RemoveItem(ctx, userID, itemID)
	if err != nil {
		span.RecordError(err)
		clog.ErrorContext(ctx, "Failed to remove cart item", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Cart item removed"})
}

// Legacy function wrappers for backward compatibility
var handler *CartHandler

func SetCartService(cartService *logicv1.CartService) {
	handler = NewCartHandler(cartService)
}

func GetCart(c *gin.Context) {
	if handler != nil {
		handler.GetCart(c)
	}
}

func AddToCart(c *gin.Context) {
	if handler != nil {
		handler.AddToCart(c)
	}
}

func GetCartCount(c *gin.Context) {
	if handler != nil {
		handler.GetCartCount(c)
	}
}

func UpdateCartItem(c *gin.Context) {
	if handler != nil {
		handler.UpdateCartItem(c)
	}
}

func RemoveCartItem(c *gin.Context) {
	if handler != nil {
		handler.RemoveCartItem(c)
	}
}
