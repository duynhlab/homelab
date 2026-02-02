package v1

import (
	"context"
	"testing"

	"github.com/duynhne/monitoring/services/cart/internal/core/domain"
)

// MockCartRepository
type MockCartRepository struct {
	addItemFunc func(ctx context.Context, userID string, item domain.CartItem) error
	clearFunc   func(ctx context.Context, userID string) error
}

func (m *MockCartRepository) FindByUserID(ctx context.Context, userID string) (*domain.Cart, error) {
	return nil, nil
}
func (m *MockCartRepository) GetItemCount(ctx context.Context, userID string) (int, error) {
	return 0, nil
}
func (m *MockCartRepository) AddItem(ctx context.Context, userID string, item domain.CartItem) error {
	if m.addItemFunc != nil {
		return m.addItemFunc(ctx, userID, item)
	}
	return nil
}
func (m *MockCartRepository) UpdateItem(ctx context.Context, userID, itemID string, quantity int) error {
	return nil
}
func (m *MockCartRepository) RemoveItem(ctx context.Context, userID, itemID string) error {
	return nil
}
func (m *MockCartRepository) Clear(ctx context.Context, userID string) error {
	if m.clearFunc != nil {
		return m.clearFunc(ctx, userID)
	}
	return nil
}

func TestAddToCart(t *testing.T) {
	ctx := context.Background()

	tests := []struct {
		name    string
		req     domain.AddToCartRequest
		wantErr bool
	}{
		{
			name: "Valid Item",
			req: domain.AddToCartRequest{
				ProductID:    "p1",
				ProductName:  "Product 1",
				ProductPrice: 100.0,
				Quantity:     1,
			},
			wantErr: false,
		},
		{
			name: "Invalid Quantity",
			req: domain.AddToCartRequest{
				ProductID:    "p1",
				ProductName:  "Product 1",
				ProductPrice: 100.0,
				Quantity:     0,
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockRepo := &MockCartRepository{}
			service := NewCartService(mockRepo)

			_, err := service.AddToCart(ctx, "user1", tt.req)
			if (err != nil) != tt.wantErr {
				t.Errorf("AddToCart() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestClearCart(t *testing.T) {
	ctx := context.Background()

	called := false
	var gotUserID string

	mockRepo := &MockCartRepository{
		clearFunc: func(ctx context.Context, userID string) error {
			called = true
			gotUserID = userID
			return nil
		},
	}
	service := NewCartService(mockRepo)

	if err := service.ClearCart(ctx, "user1"); err != nil {
		t.Fatalf("ClearCart() error = %v, want nil", err)
	}
	if !called {
		t.Fatalf("expected repository Clear to be called")
	}
	if gotUserID != "user1" {
		t.Fatalf("ClearCart() userID = %q, want %q", gotUserID, "user1")
	}
}
