package domain

import "time"

// Order represents an order aggregate
type Order struct {
	ID        string      `json:"id"`
	UserID    string      `json:"user_id"`
	Status    string      `json:"status"`
	Items     []OrderItem `json:"items"`
	Subtotal  float64     `json:"subtotal"`
	Shipping  float64     `json:"shipping"`
	Total     float64     `json:"total"`
	CreatedAt time.Time   `json:"created_at"`
}

// OrderItem represents an item in an order
type OrderItem struct {
	ProductID   string  `json:"product_id"`
	ProductName string  `json:"product_name"`
	Quantity    int     `json:"quantity"`
	Price       float64 `json:"price"`
	Subtotal    float64 `json:"subtotal"`
}

// CreateOrderRequest represents a request to create an order
type CreateOrderRequest struct {
	UserID string      `json:"user_id"`
	Items  []OrderItem `json:"items" binding:"required"`
}
