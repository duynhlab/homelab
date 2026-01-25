package v1

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
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
	err := db.QueryRow(ctx, insertQuery, userID, req.Subject, req.Body, "email", false).Scan(&notificationID)
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
	err := db.QueryRow(ctx, insertQuery, userID, "SMS", req.Message, "sms", false).Scan(&notificationID)
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

// ListNotifications returns all notifications for a user
func (s *NotificationService) ListNotifications(ctx context.Context, userID string) ([]domain.Notification, error) {
	ctx, span := middleware.StartSpan(ctx, "notification.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v1"),
		attribute.String("user_id", userID),
	))
	defer span.End()

	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Use provided userID or default to "1"
	uid := 1
	if userID != "" {
		if parsed, err := strconv.Atoi(userID); err == nil {
			uid = parsed
		}
	}

	query := `SELECT id, user_id, title, message, type, read, created_at FROM notifications WHERE user_id = $1 ORDER BY created_at DESC`
	rows, err := db.Query(ctx, query, uid)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("query notifications: %w", err)
	}
	defer rows.Close()

	var notifications []domain.Notification
	for rows.Next() {
		var notificationID, dbUserID int
		var title, message, notifType *string
		var read bool
		var createdAt time.Time

		err := rows.Scan(&notificationID, &dbUserID, &title, &message, &notifType, &read, &createdAt)
		if err != nil {
			span.RecordError(err)
			continue
		}

		notif := domain.Notification{
			ID:        strconv.Itoa(notificationID),
			Status:    "sent",
			Read:      read,
			CreatedAt: createdAt.Format(time.RFC3339),
		}
		if title != nil {
			notif.Title = *title
			notif.Message = *title // For backward compat, use title as message if no separate message
		}
		if message != nil && *message != "" {
			notif.Message = *message
		}
		if notifType != nil {
			notif.Type = *notifType
		}

		notifications = append(notifications, notif)
	}

	if err = rows.Err(); err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("scan notifications: %w", err)
	}

	span.SetAttributes(attribute.Int("notifications.count", len(notifications)))
	return notifications, nil
}

// GetNotification retrieves a single notification by ID
func (s *NotificationService) GetNotification(ctx context.Context, id string) (*domain.Notification, error) {
	ctx, span := middleware.StartSpan(ctx, "notification.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v1"),
		attribute.String("notification.id", id),
	))
	defer span.End()

	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	notificationID, err := strconv.Atoi(id)
	if err != nil {
		span.SetAttributes(attribute.Bool("notification.found", false))
		return nil, fmt.Errorf("invalid notification id %q: %w", id, ErrNotificationNotFound)
	}

	query := `SELECT id, user_id, title, message, type, read, created_at FROM notifications WHERE id = $1`
	var userID int
	var title, message, notifType *string
	var read bool
	var createdAt time.Time

	err = db.QueryRow(ctx, query, notificationID).Scan(&notificationID, &userID, &title, &message, &notifType, &read, &createdAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			span.SetAttributes(attribute.Bool("notification.found", false))
			return nil, fmt.Errorf("get notification by id %q: %w", id, ErrNotificationNotFound)
		}
		span.RecordError(err)
		return nil, fmt.Errorf("query notification: %w", err)
	}

	notification := &domain.Notification{
		ID:        strconv.Itoa(notificationID),
		Status:    "sent",
		Read:      read,
		CreatedAt: createdAt.Format(time.RFC3339),
	}
	if title != nil {
		notification.Title = *title
		notification.Message = *title
	}
	if message != nil && *message != "" {
		notification.Message = *message
	}
	if notifType != nil {
		notification.Type = *notifType
	}

	span.SetAttributes(attribute.Bool("notification.found", true))
	return notification, nil
}

// MarkAsRead marks a notification as read
func (s *NotificationService) MarkAsRead(ctx context.Context, id string) (*domain.Notification, error) {
	ctx, span := middleware.StartSpan(ctx, "notification.mark_read", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v1"),
		attribute.String("notification.id", id),
	))
	defer span.End()

	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	notificationID, err := strconv.Atoi(id)
	if err != nil {
		return nil, fmt.Errorf("invalid notification id %q: %w", id, ErrNotificationNotFound)
	}

	// Update notification to read
	updateQuery := `UPDATE notifications SET read = true WHERE id = $1`
	result, err := db.Exec(ctx, updateQuery, notificationID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("update notification: %w", err)
	}

	if result.RowsAffected() == 0 {
		return nil, fmt.Errorf("notification id %q: %w", id, ErrNotificationNotFound)
	}

	// Return updated notification
	return s.GetNotification(ctx, id)
}
