package v1

import (
	"context"
	"errors"

	"github.com/duynhne/monitoring/services/order/internal/core/domain"
	"github.com/duynhne/monitoring/services/order/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// OrderService handles order business logic
type OrderService struct {
	orderRepo domain.OrderRepository
	txManager domain.TransactionManager
}

// NewOrderService creates a new OrderService with repository injection
func NewOrderService(orderRepo domain.OrderRepository, txManager domain.TransactionManager) *OrderService {
	return &OrderService{
		orderRepo: orderRepo,
		txManager: txManager,
	}
}

// ListOrders retrieves all orders for a user
func (s *OrderService) ListOrders(ctx context.Context, userID string) ([]domain.Order, error) {
	ctx, span := middleware.StartSpan(ctx, "order.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("user.id", userID),
	))
	defer span.End()

	// Call repository
	orders, err := s.orderRepo.FindByUserID(ctx, userID)
	if err != nil {
		span.RecordError(err)
		return nil, err
	}

	span.SetAttributes(attribute.Int("orders.count", len(orders)))
	return orders, nil
}

// GetOrder retrieves a single order by ID
func (s *OrderService) GetOrder(ctx context.Context, id string) (*domain.Order, error) {
	ctx, span := middleware.StartSpan(ctx, "order.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("order.id", id),
	))
	defer span.End()

	// Call repository
	order, err := s.orderRepo.FindByID(ctx, id)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			span.SetAttributes(attribute.Bool("order.found", false))
			return nil, ErrOrderNotFound
		}
		span.RecordError(err)
		return nil, err
	}

	span.SetAttributes(attribute.Bool("order.found", true))
	return order, nil
}

// CreateOrder creates a new order with transaction support
func (s *OrderService) CreateOrder(ctx context.Context, req domain.CreateOrderRequest) (*domain.Order, error) {
	ctx, span := middleware.StartSpan(ctx, "order.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("user.id", req.UserID),
	))
	defer span.End()

	// Business validation
	if len(req.Items) == 0 {
		span.SetAttributes(attribute.Bool("order.created", false))
		return nil, ErrInvalidOrder
	}

	// Calculate total
	var subtotal float64
	for _, item := range req.Items {
		subtotal += item.Price * float64(item.Quantity)
	}

	// Create order domain model
	order := &domain.Order{
		UserID:   req.UserID,
		Items:    req.Items,
		Subtotal: subtotal,
		Shipping: 5.00, // Fixed shipping for demo
		Total:    subtotal + 5.00,
		Status:   "pending",
	}

	// Begin transaction
	tx, err := s.txManager.Begin(ctx)
	if err != nil {
		span.RecordError(err)
		return nil, err
	}
	defer tx.Rollback() // Rollback if not committed

	// Create order with transaction
	err = s.orderRepo.CreateWithTx(ctx, tx, order)
	if err != nil {
		span.RecordError(err)
		return nil, err
	}

	// TODO: Update inventory (when inventory service is available)
	// for _, item := range order.Items {
	//     err = s.inventoryRepo.DecrementStockWithTx(ctx, tx, item.ProductID, item.Quantity)
	//     if err != nil {
	//         return nil, ErrInsufficientStock
	//     }
	// }

	// TODO: Clear cart (when cart clearing with transaction is needed)
	// err = s.cartRepo.ClearWithTx(ctx, tx, req.UserID)
	// if err != nil {
	//     return nil, err
	// }

	// Commit transaction
	if err := tx.Commit(); err != nil {
		span.RecordError(err)
		return nil, err
	}

	span.SetAttributes(
		attribute.String("order.id", order.ID),
		attribute.Bool("order.created", true),
	)
	span.AddEvent("order.created")

	return order, nil
}

// UpdateOrderStatus updates the status of an order
func (s *OrderService) UpdateOrderStatus(ctx context.Context, id, status string) error {
	ctx, span := middleware.StartSpan(ctx, "order.update_status", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("order.id", id),
		attribute.String("status", status),
	))
	defer span.End()

	// Call repository
	err := s.orderRepo.UpdateStatus(ctx, id, status)
	if err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			return ErrOrderNotFound
		}
		span.RecordError(err)
		return err
	}

	span.SetAttributes(attribute.Bool("status.updated", true))
	return nil
}
