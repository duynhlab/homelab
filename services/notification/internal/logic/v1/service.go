package v1

import (
	"context"
	"fmt"
	"strconv"

	database "github.com/duynhne/monitoring/services/notification/internal/core"
	"github.com/duynhne/monitoring/services/notification/internal/core/domain"
	"github.com/duynhne/monitoring/services/notification/middleware"
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

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Validate recipient
	if req.To == "" || req.To == "invalid" {
		span.SetAttributes(attribute.Bool("email.sent", false))
		return nil, fmt.Errorf("send email to %q: %w", req.To, ErrInvalidRecipient)
	}

	// TODO: Extract user_id from email or JWT token
	// For now, use mock user_id = 1
	userID := 1

	// Insert notification into database
	insertQuery := `INSERT INTO notifications (user_id, title, message, type, read) VALUES ($1, $2, $3, $4, $5) RETURNING id`
	var notificationID int
	err := db.QueryRowContext(ctx, insertQuery, userID, req.Subject, req.Body, "email", false).Scan(&notificationID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("insert notification: %w", err)
	}

	notification := &domain.Notification{
		ID:      strconv.Itoa(notificationID),
		Type:    "email",
		Message: req.Subject,
		Status:  "sent",
	}

	span.SetAttributes(attribute.Bool("email.sent", true))
	span.AddEvent("notification.email.sent")

	return notification, nil
}

func (s *NotificationService) SendSMS(ctx context.Context, req domain.SendSMSRequest) (*domain.Notification, error) {
	ctx, span := middleware.StartSpan(ctx, "notification.sms", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("to", req.To),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// TODO: Extract user_id from phone number or JWT token
	userID := 1

	// Insert notification
	insertQuery := `INSERT INTO notifications (user_id, title, message, type, read) VALUES ($1, $2, $3, $4, $5) RETURNING id`
	var notificationID int
	err := db.QueryRowContext(ctx, insertQuery, userID, "SMS", req.Message, "sms", false).Scan(&notificationID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("insert notification: %w", err)
	}

	notification := &domain.Notification{
		ID:      strconv.Itoa(notificationID),
		Type:    "sms",
		Message: req.Message,
		Status:  "sent",
	}

	span.SetAttributes(attribute.Bool("sms.sent", true))
	span.AddEvent("notification.sms.sent")

	return notification, nil
}
