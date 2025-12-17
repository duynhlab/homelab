package domain

type Order struct {
	ID     string      `json:"id"`
	Status string      `json:"status"`
	Items  []OrderItem `json:"items"`
	Total  float64     `json:"total"`
}

type OrderItem struct {
	ProductID string  `json:"productId"`
	Quantity  int     `json:"quantity"`
	Price     float64 `json:"price"`
}

type CreateOrderRequest struct {
	Items []OrderItem `json:"items" binding:"required"`
}
