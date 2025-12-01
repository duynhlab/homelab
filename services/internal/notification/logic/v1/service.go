package v1

import (
	"context"

	"github.com/duynhne/monitoring/internal/notification/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type NotificationService struct{}

func NewNotificationService() *NotificationService {
	return &NotificationService{}
}

func (s *NotificationService) SendEmail(ctx context.Context, req domain.SendEmailRequest) (*domain.Notification, error) {
	ctx, span := middleware.StartSpan(ctx, "notification.email", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("to", req.To),
	))
	defer span.End()

	notification := &domain.Notification{
		ID:      "email-1",
		Type:    "email",
		Message: req.Subject,
		Status:  "sent",
	}
	return notification, nil
}

func (s *NotificationService) SendSMS(ctx context.Context, req domain.SendSMSRequest) (*domain.Notification, error) {
	ctx, span := middleware.StartSpan(ctx, "notification.sms", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("to", req.To),
	))
	defer span.End()

	notification := &domain.Notification{
		ID:      "sms-1",
		Type:    "sms",
		Message: req.Message,
		Status:  "sent",
	}
	return notification, nil
}

