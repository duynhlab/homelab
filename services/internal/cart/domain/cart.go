package domain

type Cart struct {
	ID    string    `json:"id"`
	Items []CartItem `json:"items"`
	Total float64   `json:"total"`
}

type CartItem struct {
	ProductID string  `json:"productId"`
	Quantity  int     `json:"quantity"`
	Price     float64 `json:"price"`
}

type AddToCartRequest struct {
	ProductID string `json:"productId" binding:"required"`
	Quantity  int    `json:"quantity" binding:"required,min=1"`
}