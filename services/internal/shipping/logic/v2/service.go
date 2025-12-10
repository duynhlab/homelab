package v2

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

func (s *ShippingService) EstimateShipment(ctx context.Context, req domain.EstimateRequest) (map[string]interface{}, error) {
	ctx, span := middleware.StartSpan(ctx, "shipping.estimate", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("origin", req.Origin),
		attribute.String("destination", req.Destination),
	))
	defer span.End()

	// Mock logic: validate address
	if req.Destination == "" || req.Destination == "invalid" {
		span.SetAttributes(attribute.Bool("estimate.created", false))
		return nil, fmt.Errorf("estimate shipment to %q: %w", req.Destination, ErrInvalidAddress)
	}

	estimate := map[string]interface{}{
		"origin":      req.Origin,
		"destination": req.Destination,
		"weight":      req.Weight,
		"cost":        25.99,
		"days":        3,
	}
	span.SetAttributes(attribute.Bool("estimate.created", true))
	return estimate, nil
}

