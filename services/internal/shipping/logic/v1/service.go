package v1

import (
	"context"
	"fmt"

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

	// Mock logic: simulate shipment not found
	if trackingID == "999" {
		span.SetAttributes(attribute.Bool("shipment.found", false))
		return nil, fmt.Errorf("track shipment with id %q: %w", trackingID, ErrShipmentNotFound)
	}

	shipment := &domain.Shipment{
		ID:          "1",
		TrackingID:  trackingID,
		Status:      "in_transit",
		Destination: "New York",
	}
	span.SetAttributes(attribute.Bool("shipment.found", true))
	return shipment, nil
}

