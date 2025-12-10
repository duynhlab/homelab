package v2

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/duynhne/monitoring/internal/order/core/domain"
	logicv2 "github.com/duynhne/monitoring/internal/order/logic/v2"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

var orderService = logicv2.NewOrderService()

func ListOrders(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	orders, err := orderService.ListOrders(ctx)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to list orders", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Orders listed", zap.Int("count", len(orders)))
	c.JSON(http.StatusOK, orders)
}

func GetOrderStatus(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)
	orderId := c.Param("orderId")
	span.SetAttributes(attribute.String("order.id", orderId))

	status, err := orderService.GetOrderStatus(ctx, orderId)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to get order status", zap.Error(err))
		
		switch {
		case errors.Is(err, logicv2.ErrOrderNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Order status retrieved", zap.String("order_id", orderId))
	c.JSON(http.StatusOK, status)
}

func CreateOrder(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
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
	order, err := orderService.CreateOrder(ctx, req)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to create order", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Order created", zap.String("order_id", order.ID))
	c.JSON(http.StatusCreated, order)
}

