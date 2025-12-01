package v2

import (
	"net/http"

	"github.com/gin-gonic/gin"
	logicv2 "github.com/duynhne/monitoring/internal/notification/logic/v2"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

var notificationService = logicv2.NewNotificationService()

func ListNotifications(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	notifications, err := notificationService.ListNotifications(ctx)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to list notifications", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Notifications listed", zap.Int("count", len(notifications)))
	c.JSON(http.StatusOK, notifications)
}

func GetNotification(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)
	id := c.Param("id")
	span.SetAttributes(attribute.String("notification.id", id))

	notification, err := notificationService.GetNotification(ctx, id)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to get notification", zap.Error(err), zap.String("notification_id", id))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Notification retrieved", zap.String("notification_id", id))
	c.JSON(http.StatusOK, notification)
}

