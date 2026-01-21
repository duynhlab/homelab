package domain

// Cart represents a shopping cart aggregate
type Cart struct {
	UserID    string     `json:"user_id"`
	Items     []CartItem `json:"items"`
	Subtotal  float64    `json:"subtotal"`
	Shipping  float64    `json:"shipping"`
	Total     float64    `json:"total"`
	ItemCount int        `json:"item_count"`
}

// CartItem represents an item in the cart
type CartItem struct {
	ID           string  `json:"id"`
	ProductID    string  `json:"product_id"`
	ProductName  string  `json:"product_name"`
	ProductPrice float64 `json:"product_price"`
	Quantity     int     `json:"quantity"`
	Subtotal     float64 `json:"subtotal"`
}

// AddToCartRequest represents a request to add an item to cart
type AddToCartRequest struct {
	ProductID    string  `json:"product_id" binding:"required"`
	ProductName  string  `json:"product_name" binding:"required"`
	ProductPrice float64 `json:"product_price" binding:"required,min=0"`
	Quantity     int     `json:"quantity" binding:"required,min=1"`
}
