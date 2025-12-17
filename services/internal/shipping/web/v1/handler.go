package v1

import (
	"errors"
	"net/http"

	logicv1 "github.com/duynhne/monitoring/internal/shipping/logic/v1"
	"github.com/duynhne/monitoring/pkg/middleware"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

var shippingService = logicv1.NewShippingService()

func TrackShipment(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)
	trackingID := c.Query("trackingId")
	span.SetAttributes(attribute.String("tracking.id", trackingID))

	shipment, err := shippingService.TrackShipment(ctx, trackingID)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to track shipment", zap.Error(err))

		switch {
		case errors.Is(err, logicv1.ErrShipmentNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "Shipment not found"})
		case errors.Is(err, logicv1.ErrCarrierUnavailable):
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Carrier unavailable"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Shipment tracked", zap.String("tracking_id", trackingID))
	c.JSON(http.StatusOK, shipment)
}
