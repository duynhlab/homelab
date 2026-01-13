package v2

import (
	"errors"
	"net/http"

	logicv2 "github.com/duynhne/monitoring/services/product/internal/logic/v2"
	"github.com/duynhne/monitoring/services/product/middleware"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

var productService = logicv2.NewProductService()

func ListItems(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	items, err := productService.ListItems(ctx)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to list items", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Items listed", zap.Int("count", len(items)))
	c.JSON(http.StatusOK, items)
}

func GetItem(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)
	itemId := c.Param("itemId")
	span.SetAttributes(attribute.String("item.id", itemId))

	item, err := productService.GetItem(ctx, itemId)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to get item", zap.Error(err))

		switch {
		case errors.Is(err, logicv2.ErrProductNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "Product not found"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Item retrieved", zap.String("item_id", itemId))
	c.JSON(http.StatusOK, item)
}

func CreateItem(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	var req logicv2.CreateItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		span.SetAttributes(attribute.Bool("request.valid", false))
		span.RecordError(err)
		zapLogger.Error("Invalid request", zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	span.SetAttributes(attribute.Bool("request.valid", true))
	item, err := productService.CreateItem(ctx, req)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to create item", zap.Error(err))

		switch {
		case errors.Is(err, logicv2.ErrInvalidPrice):
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid price"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Item created", zap.String("item_id", item.ItemID))
	c.JSON(http.StatusCreated, item)
}
