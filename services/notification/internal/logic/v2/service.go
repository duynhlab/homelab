package v2

import (
	"context"
	"errors"
	"fmt"
	"strconv"

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

func (s *NotificationService) ListNotifications(ctx context.Context) ([]domain.Notification, error) {
	ctx, span := middleware.StartSpan(ctx, "notification.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
	))
	defer span.End()

	// Get database connection pool (pgx)
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// TODO: Extract user_id from JWT token or session context
	userID := 1

	// Query notifications
	query := `SELECT id, user_id, title, message, type FROM notifications WHERE user_id = $1 ORDER BY created_at DESC`
	rows, err := db.Query(ctx, query, userID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("query notifications: %w", err)
	}
	defer rows.Close()

	var notifications []domain.Notification
	for rows.Next() {
		var notificationID int
		var title, message, notifType *string // Use pointers for nullable columns

		err := rows.Scan(&notificationID, &userID, &title, &message, &notifType)
		if err != nil {
			span.RecordError(err)
			continue
		}

		notif := domain.Notification{
			ID:     strconv.Itoa(notificationID),
			Status: "sent",
		}
		if title != nil {
			notif.Message = *title
		} else if message != nil {
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

func (s *NotificationService) GetNotification(ctx context.Context, id string) (*domain.Notification, error) {
	ctx, span := middleware.StartSpan(ctx, "notification.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("notification.id", id),
	))
	defer span.End()

	// Get database connection pool (pgx)
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

	// Query notification - use pointers for nullable columns
	query := `SELECT id, user_id, title, message, type, read FROM notifications WHERE id = $1`
	var userID int
	var title, message, notifType *string
	var read bool

	err = db.QueryRow(ctx, query, notificationID).Scan(&notificationID, &userID, &title, &message, &notifType, &read)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
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
	if title != nil {
		notification.Message = *title
	} else if message != nil {
		notification.Message = *message
	}
	if notifType != nil {
		notification.Type = *notifType
	}

	span.SetAttributes(attribute.Bool("notification.found", true))
	return notification, nil
}
