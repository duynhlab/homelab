package v2

import (
	"context"
	"database/sql"
	"fmt"

	database "github.com/duynhne/monitoring/services/shipping-v2/internal/core"
	"github.com/duynhne/monitoring/services/shipping-v2/internal/core/domain"
	"github.com/duynhne/monitoring/services/shipping-v2/middleware"
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
		attribute.Float64("weight", req.Weight),
	))
	defer span.End()

	// Validate request
	if req.Destination == "" || req.Destination == "invalid" {
		span.SetAttributes(attribute.Bool("estimate.created", false))
		return nil, fmt.Errorf("estimate shipment to %q: %w", req.Destination, ErrInvalidAddress)
	}

	// Get database connection
	db := database.GetDB()
	if db == nil {
		span.RecordError(fmt.Errorf("database connection not available"))
		return nil, fmt.Errorf("database connection not available")
	}

	// Query shipment_estimates table
	query := `
		SELECT cost, estimated_days, carrier 
		FROM shipment_estimates 
		WHERE origin = $1 AND destination = $2 AND weight = $3
		ORDER BY created_at DESC
		LIMIT 1
	`

	var cost float64
	var estimatedDays int
	var carrier sql.NullString

	err := db.QueryRowContext(ctx, query, req.Origin, req.Destination, req.Weight).Scan(&cost, &estimatedDays, &carrier)
	if err != nil {
		if err == sql.ErrNoRows {
			// No matching estimate found - calculate default estimate
			span.SetAttributes(attribute.Bool("estimate.found_in_db", false))
			estimate := map[string]interface{}{
				"origin":      req.Origin,
				"destination": req.Destination,
				"weight":      req.Weight,
				"cost":        25.99, // Default cost
				"days":        3,     // Default days
			}
			span.SetAttributes(attribute.Bool("estimate.created", true))
			return estimate, nil
		}
		span.RecordError(err)
		return nil, fmt.Errorf("query shipment estimate: %w", err)
	}

	// Found matching estimate in database
	span.SetAttributes(
		attribute.Bool("estimate.found_in_db", true),
		attribute.Float64("estimate.cost", cost),
		attribute.Int("estimate.days", estimatedDays),
	)

	estimate := map[string]interface{}{
		"origin":      req.Origin,
		"destination": req.Destination,
		"weight":      req.Weight,
		"cost":        cost,
		"days":        estimatedDays,
	}

	if carrier.Valid {
		estimate["carrier"] = carrier.String
		span.SetAttributes(attribute.String("estimate.carrier", carrier.String))
	}

	span.SetAttributes(attribute.Bool("estimate.created", true))
	return estimate, nil
}
