package v1

import (
	"errors"
	"net/http"

	"github.com/duynhne/monitoring/services/order/internal/core/domain"
	logicv1 "github.com/duynhne/monitoring/services/order/internal/logic/v1"
	"github.com/duynhne/monitoring/services/order/middleware"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

// OrderHandler holds the order service dependency
type OrderHandler struct {
	orderService *logicv1.OrderService
}

// NewOrderHandler creates a new order handler with dependency injection
func NewOrderHandler(orderService *logicv1.OrderService) *OrderHandler {
	return &OrderHandler{orderService: orderService}
}

func (h *OrderHandler) ListOrders(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	// Get userID from context/auth (for now, use a placeholder)
	userID := c.GetString("user_id")
	if userID == "" {
		userID = "1" // Default for demo
	}

	orders, err := h.orderService.ListOrders(ctx, userID)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to list orders", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Orders listed", zap.Int("count", len(orders)))
	c.JSON(http.StatusOK, orders)
}

func (h *OrderHandler) GetOrder(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)
	id := c.Param("id")
	span.SetAttributes(attribute.String("order.id", id))

	order, err := h.orderService.GetOrder(ctx, id)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to get order", zap.Error(err))

		switch {
		case errors.Is(err, logicv1.ErrOrderNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Order retrieved", zap.String("order_id", id))
	c.JSON(http.StatusOK, order)
}

func (h *OrderHandler) CreateOrder(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	var req domain.CreateOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		span.SetAttributes(attribute.Bool("request.valid", false))
		span.RecordError(err)
		zapLogger.Error("Invalid request", zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	span.SetAttributes(attribute.Bool("request.valid", true))
	order, err := h.orderService.CreateOrder(ctx, req)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to create order", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Order created", zap.String("order_id", order.ID))
	c.JSON(http.StatusCreated, order)
}

// Legacy function wrappers for backward compatibility
var handler *OrderHandler

func SetOrderService(orderService *logicv1.OrderService) {
	handler = NewOrderHandler(orderService)
}

func ListOrders(c *gin.Context) {
	if handler != nil {
		handler.ListOrders(c)
	}
}

func GetOrder(c *gin.Context) {
	if handler != nil {
		handler.GetOrder(c)
	}
}

func CreateOrder(c *gin.Context) {
	if handler != nil {
		handler.CreateOrder(c)
	}
}
