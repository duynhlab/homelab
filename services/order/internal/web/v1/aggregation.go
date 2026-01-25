package v1

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/duynhne/monitoring/services/order/middleware"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"

	logicv1 "github.com/duynhne/monitoring/services/order/internal/logic/v1"
)

// ShippingClient handles HTTP calls to the shipping service
type ShippingClient struct {
	baseURL    string
	httpClient *http.Client
}

// Shipment represents a shipment response from the shipping service
type Shipment struct {
	ID                int     `json:"id"`
	OrderID           int     `json:"order_id"`
	TrackingNumber    string  `json:"tracking_number"`
	Carrier           string  `json:"carrier,omitempty"`
	Status            string  `json:"status"`
	EstimatedDelivery *string `json:"estimated_delivery,omitempty"`
	CreatedAt         string  `json:"created_at"`
	UpdatedAt         string  `json:"updated_at"`
}

// OrderDetailsResponse is the aggregated response containing order and shipment
type OrderDetailsResponse struct {
	Order    interface{} `json:"order"`
	Shipment *Shipment   `json:"shipment,omitempty"`
}

// NewShippingClient creates a new shipping service client
func NewShippingClient(baseURL string) *ShippingClient {
	return &ShippingClient{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

// GetShipmentByOrderID fetches shipment info for an order
func (c *ShippingClient) GetShipmentByOrderID(orderID string) (*Shipment, error) {
	url := fmt.Sprintf("%s/api/v1/shipping/orders/%s", c.baseURL, orderID)

	resp, err := c.httpClient.Get(url)
	if err != nil {
		return nil, fmt.Errorf("shipping service call failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		// No shipment yet - this is not an error
		return nil, nil
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("shipping service returned status %d", resp.StatusCode)
	}

	var shipment Shipment
	if err := json.NewDecoder(resp.Body).Decode(&shipment); err != nil {
		return nil, fmt.Errorf("failed to decode shipment response: %w", err)
	}

	return &shipment, nil
}

// Global shipping client (set during init)
var shippingClient *ShippingClient

// SetShippingClient sets the shipping client for aggregation handlers
func SetShippingClient(client *ShippingClient) {
	shippingClient = client
}

// GetOrderDetails handles GET /api/v1/orders/:id/details
// Returns order with shipment info (aggregation endpoint)
func GetOrderDetails(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
		attribute.String("endpoint.type", "aggregation"),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)
	orderID := c.Param("id")
	span.SetAttributes(attribute.String("order.id", orderID))

	// Get order from handler (use the global handler)
	if handler == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Service not initialized"})
		return
	}

	order, err := handler.orderService.GetOrder(ctx, orderID)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to get order", zap.Error(err), zap.String("order_id", orderID))

		switch {
		case errors.Is(err, logicv1.ErrOrderNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "Order not found"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	// Try to get shipment (non-blocking - order may not have shipment yet)
	var shipment *Shipment
	if shippingClient != nil {
		shipment, err = shippingClient.GetShipmentByOrderID(orderID)
		if err != nil {
			// Log but don't fail - shipment is optional
			zapLogger.Warn("Could not fetch shipment", zap.Error(err), zap.String("order_id", orderID))
			span.SetAttributes(attribute.Bool("shipment.fetch_error", true))
		}
		if shipment != nil {
			span.SetAttributes(
				attribute.Bool("shipment.found", true),
				attribute.String("shipment.status", shipment.Status),
			)
		} else {
			span.SetAttributes(attribute.Bool("shipment.found", false))
		}
	}

	response := OrderDetailsResponse{
		Order:    order,
		Shipment: shipment,
	}

	zapLogger.Info("Order details retrieved",
		zap.String("order_id", orderID),
		zap.Bool("has_shipment", shipment != nil),
	)
	c.JSON(http.StatusOK, response)
}
