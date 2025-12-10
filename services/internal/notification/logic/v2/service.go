package v2

import (
	"context"
	"fmt"

	"github.com/duynhne/monitoring/internal/notification/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type NotificationService struct{}

func NewNotificationService() *NotificationService {
	return &NotificationService{}
}

func (s *NotificationService) ListNotifications(ctx context.Context) ([]domain.Notification, error) {
	ctx, span := middleware.StartSpan(ctx, "notification.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
	))
	defer span.End()

	notifications := []domain.Notification{
		{ID: "1", Type: "email", Message: "Welcome!", Status: "sent"},
		{ID: "2", Type: "sms", Message: "Order confirmed", Status: "delivered"},
	}
	return notifications, nil
}

func (s *NotificationService) GetNotification(ctx context.Context, id string) (*domain.Notification, error) {
	ctx, span := middleware.StartSpan(ctx, "notification.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("notification.id", id),
	))
	defer span.End()

	// Mock logic: simulate notification not found
	if id == "999" {
		span.SetAttributes(attribute.Bool("notification.found", false))
		return nil, fmt.Errorf("get notification by id %q: %w", id, ErrNotificationNotFound)
	}

	notification := &domain.Notification{
		ID:      id,
		Type:    "email",
		Message: "Notification details",
		Status:  "sent",
	}
	span.SetAttributes(attribute.Bool("notification.found", true))
	return notification, nil
}

