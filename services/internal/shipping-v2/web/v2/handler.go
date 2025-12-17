package v2

import (
	"errors"
	"net/http"

	"github.com/duynhne/monitoring/internal/shipping-v2/core/domain"
	logicv2 "github.com/duynhne/monitoring/internal/shipping-v2/logic/v2"
	"github.com/duynhne/monitoring/pkg/middleware"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

var shippingService = logicv2.NewShippingService()

func EstimateShipment(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	var req domain.EstimateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		span.SetAttributes(attribute.Bool("request.valid", false))
		span.RecordError(err)
		zapLogger.Error("Invalid request", zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	span.SetAttributes(attribute.Bool("request.valid", true))
	estimate, err := shippingService.EstimateShipment(ctx, req)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to estimate shipment", zap.Error(err))

		switch {
		case errors.Is(err, logicv2.ErrInvalidAddress):
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid address"})
		case errors.Is(err, logicv2.ErrCarrierUnavailable):
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Carrier unavailable"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Shipment estimated")
	c.JSON(http.StatusOK, estimate)
}
