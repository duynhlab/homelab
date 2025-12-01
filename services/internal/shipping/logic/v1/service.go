package v1

import (
	"context"

	"github.com/duynhne/monitoring/internal/shipping/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type ShippingService struct{}

func NewShippingService() *ShippingService {
	return &ShippingService{}
}

func (s *ShippingService) TrackShipment(ctx context.Context, trackingID string) (*domain.Shipment, error) {
	ctx, span := middleware.StartSpan(ctx, "shipping.track", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("tracking.id", trackingID),
	))
	defer span.End()

	shipment := &domain.Shipment{
		ID:          "1",
		TrackingID:  trackingID,
		Status:      "in_transit",
		Destination: "New York",
	}
	return shipment, nil
}

