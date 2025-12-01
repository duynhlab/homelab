package v2

import (
	"context"

	"github.com/duynhne/monitoring/internal/order/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type OrderService struct{}

func NewOrderService() *OrderService {
	return &OrderService{}
}

func (s *OrderService) ListOrders(ctx context.Context) ([]domain.Order, error) {
	ctx, span := middleware.StartSpan(ctx, "order.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
	))
	defer span.End()

	orders := []domain.Order{
		{ID: "1", Status: "pending", Items: []domain.OrderItem{{ProductID: "1", Quantity: 2, Price: 100}}, Total: 200},
		{ID: "2", Status: "shipped", Items: []domain.OrderItem{{ProductID: "2", Quantity: 1, Price: 150}}, Total: 150},
	}
	return orders, nil
}

func (s *OrderService) GetOrderStatus(ctx context.Context, orderId string) (map[string]interface{}, error) {
	ctx, span := middleware.StartSpan(ctx, "order.status", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("order.id", orderId),
	))
	defer span.End()

	status := map[string]interface{}{
		"orderId":  orderId,
		"status":   "shipped",
		"tracking": "TRK123456",
	}
	return status, nil
}

func (s *OrderService) CreateOrder(ctx context.Context, req domain.CreateOrderRequest) (*domain.Order, error) {
	ctx, span := middleware.StartSpan(ctx, "order.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
	))
	defer span.End()

	order := &domain.Order{
		ID:     "new-order-v2",
		Status: "pending",
		Items:  req.Items,
		Total:  300,
	}
	span.SetAttributes(attribute.String("order.id", order.ID))
	return order, nil
}

