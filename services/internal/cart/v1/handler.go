package v1

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/demo/monitoring-golang/internal/cart/domain"
)

func GetCart(c *gin.Context) {
	cart := domain.Cart{
		ID: "cart-1",
		Items: []domain.CartItem{
			{ProductID: "1", Quantity: 2, Price: 100},
			{ProductID: "2", Quantity: 1, Price: 200},
		},
		Total: 400,
	}
	c.JSON(http.StatusOK, cart)
}

func AddToCart(c *gin.Context) {
	var req domain.AddToCartRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	item := domain.CartItem{
		ProductID: req.ProductID,
		Quantity:  req.Quantity,
		Price:     100, // Mock price
	}
	c.JSON(http.StatusCreated, item)
}