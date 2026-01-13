package v2

import (
	"context"
	"database/sql"
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

func (s *NotificationService) ListNotifications(ctx context.Context) ([]domain.Notification, error) {
	ctx, span := middleware.StartSpan(ctx, "notification.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// TODO: Extract user_id from JWT token or session context
	userID := 1

	// Query notifications
	query := `SELECT id, user_id, title, message, type FROM notifications WHERE user_id = $1 ORDER BY created_at DESC`
	rows, err := db.QueryContext(ctx, query, userID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("query notifications: %w", err)
	}
	defer rows.Close()

	var notifications []domain.Notification
	for rows.Next() {
		var notificationID int
		var title, message, notifType sql.NullString

		err := rows.Scan(&notificationID, &userID, &title, &message, &notifType)
		if err != nil {
			span.RecordError(err)
			continue
		}

		notif := domain.Notification{
			ID:     strconv.Itoa(notificationID),
			Status: "sent",
		}
		if title.Valid {
			notif.Message = title.String
		} else if message.Valid {
			notif.Message = message.String
		}
		if notifType.Valid {
			notif.Type = notifType.String
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

func (s *NotificationService) GetNotification(ctx context.Context, id string) (*domain.Notification, error) {
	ctx, span := middleware.StartSpan(ctx, "notification.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("notification.id", id),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Convert string ID to int
	notificationID, err := strconv.Atoi(id)
	if err != nil {
		span.SetAttributes(attribute.Bool("notification.found", false))
		return nil, fmt.Errorf("invalid notification id %q: %w", id, ErrNotificationNotFound)
	}

	// Query notification
	query := `SELECT id, user_id, title, message, type, read FROM notifications WHERE id = $1`
	var userID int
	var title, message, notifType sql.NullString
	var read bool

	err = db.QueryRowContext(ctx, query, notificationID).Scan(&notificationID, &userID, &title, &message, &notifType, &read)
	if err != nil {
		if err == sql.ErrNoRows {
			span.SetAttributes(attribute.Bool("notification.found", false))
			return nil, fmt.Errorf("get notification by id %q: %w", id, ErrNotificationNotFound)
		}
		span.RecordError(err)
		return nil, fmt.Errorf("query notification: %w", err)
	}

	notification := &domain.Notification{
		ID:     strconv.Itoa(notificationID),
		Status: "sent",
	}
	if title.Valid {
		notification.Message = title.String
	} else if message.Valid {
		notification.Message = message.String
	}
	if notifType.Valid {
		notification.Type = notifType.String
	}

	span.SetAttributes(attribute.Bool("notification.found", true))
	return notification, nil
}
