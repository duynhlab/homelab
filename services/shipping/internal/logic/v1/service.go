package v1

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	database "github.com/duynhne/monitoring/services/shipping/internal/core"
	"github.com/duynhne/monitoring/services/shipping/internal/core/domain"
	"github.com/duynhne/monitoring/services/shipping/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type ShippingService struct{}

func NewShippingService() *ShippingService {
	return &ShippingService{}
}

func (s *ShippingService) TrackShipment(ctx context.Context, trackingNumber string) (*domain.Shipment, error) {
	ctx, span := middleware.StartSpan(ctx, "shipping.track", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v1"),
		attribute.String("tracking.number", trackingNumber),
	))
	defer span.End()

	// Get database connection pool (pgx)
	db := database.GetDB()
	if db == nil {
		span.RecordError(fmt.Errorf("database connection not available"))
		return nil, fmt.Errorf("database connection not available")
	}

	// Query shipments table by tracking_number
	query := `
		SELECT id, order_id, tracking_number, carrier, status, estimated_delivery, created_at, updated_at
		FROM shipments
		WHERE tracking_number = $1
		LIMIT 1
	`

	var id, orderID int
	var trackingNum, carrier, status string
	var estimatedDelivery *time.Time // Use pointer for nullable column
	var createdAt, updatedAt time.Time

	err := db.QueryRow(ctx, query, trackingNumber).Scan(
		&id, &orderID, &trackingNum, &carrier, &status, &estimatedDelivery, &createdAt, &updatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			span.SetAttributes(attribute.Bool("shipment.found", false))
			return nil, fmt.Errorf("track shipment with number %q: %w", trackingNumber, ErrShipmentNotFound)
		}
		span.RecordError(err)
		return nil, fmt.Errorf("query shipment: %w", err)
	}

	// Map database fields to domain model
	shipment := &domain.Shipment{
		ID:             id,
		OrderID:        orderID,
		TrackingNumber: trackingNum,
		Status:         status,
		CreatedAt:      createdAt.Format(time.RFC3339),
		UpdatedAt:      updatedAt.Format(time.RFC3339),
	}

	if carrier != "" {
		shipment.Carrier = carrier
	}

	if estimatedDelivery != nil {
		deliveryStr := estimatedDelivery.Format(time.RFC3339)
		shipment.EstimatedDelivery = &deliveryStr
		span.SetAttributes(attribute.String("shipment.estimated_delivery", deliveryStr))
	}

	span.SetAttributes(
		attribute.Bool("shipment.found", true),
		attribute.Int("shipment.id", id),
		attribute.String("shipment.status", status),
		attribute.String("shipment.carrier", carrier),
	)

	return shipment, nil
}
