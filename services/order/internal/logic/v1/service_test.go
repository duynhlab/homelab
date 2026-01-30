package v1

import (
	"context"
	"testing"

	"github.com/duynhne/monitoring/services/order/internal/core/domain"
)

// MockTransaction
type MockTransaction struct {
	commitCalled   bool
	rollbackCalled bool
}

func (m *MockTransaction) Commit(ctx context.Context) error {
	m.commitCalled = true
	return nil
}

func (m *MockTransaction) Rollback(ctx context.Context) error {
	m.rollbackCalled = true
	return nil
}

// MockTransactionManager
type MockTransactionManager struct{}

func (m *MockTransactionManager) Begin(ctx context.Context) (domain.Transaction, error) {
	return &MockTransaction{}, nil
}

// MockOrderRepository
type MockOrderRepository struct {
	createWithTxFunc func(ctx context.Context, tx domain.Transaction, order *domain.Order) error
}

func (m *MockOrderRepository) FindByID(ctx context.Context, id string) (*domain.Order, error) {
	return nil, nil
}
func (m *MockOrderRepository) FindByUserID(ctx context.Context, userID string) ([]domain.Order, error) {
	return nil, nil
}
func (m *MockOrderRepository) Create(ctx context.Context, order *domain.Order) error {
	return nil
}
func (m *MockOrderRepository) UpdateStatus(ctx context.Context, id, status string) error {
	return nil
}
func (m *MockOrderRepository) CreateWithTx(ctx context.Context, tx domain.Transaction, order *domain.Order) error {
	if m.createWithTxFunc != nil {
		return m.createWithTxFunc(ctx, tx, order)
	}
	return nil
}

func TestCreateOrder(t *testing.T) {
	ctx := context.Background()

	tests := []struct {
		name         string
		req          domain.CreateOrderRequest
		wantSubtotal float64
		wantErr      bool
	}{
		{
			name: "Valid Order",
			req: domain.CreateOrderRequest{
				UserID: "user1",
				Items: []domain.OrderItem{
					{ProductID: "p1", Quantity: 2, Price: 10.0}, // 20.0
					{ProductID: "p2", Quantity: 1, Price: 5.0},  // 5.0
				},
			},
			wantSubtotal: 25.0,
			wantErr:      false,
		},
		{
			name: "Empty Items",
			req: domain.CreateOrderRequest{
				UserID: "user1",
				Items:  []domain.OrderItem{},
			},
			wantSubtotal: 0,
			wantErr:      true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockRepo := &MockOrderRepository{}
			mockTxManager := &MockTransactionManager{}
			service := NewOrderService(mockRepo, mockTxManager)

			order, err := service.CreateOrder(ctx, tt.req)
			if (err != nil) != tt.wantErr {
				t.Errorf("CreateOrder() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if !tt.wantErr && order != nil {
				if order.Subtotal != tt.wantSubtotal {
					t.Errorf("CreateOrder() subtotal = %v, want %v", order.Subtotal, tt.wantSubtotal)
				}
				// Verify Total = Subtotal + Shipping (5.00)
				expectedTotal := tt.wantSubtotal + 5.00
				if order.Total != expectedTotal {
					t.Errorf("CreateOrder() total = %v, want %v", order.Total, expectedTotal)
				}
			}
		})
	}
}
