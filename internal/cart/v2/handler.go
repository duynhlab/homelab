package v2

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/demo/monitoring-golang/internal/cart/domain"
)

func GetCart(c *gin.Context) {
	cartId := c.Param("cartId")
	cart := domain.Cart{
		ID: cartId,
		Items: []domain.CartItem{
			{ProductID: "1", Quantity: 2, Price: 100},
			{ProductID: "2", Quantity: 1, Price: 200},
		},
		Total: 400,
	}
	c.JSON(http.StatusOK, cart)
}

func AddItem(c *gin.Context) {
	cartId := c.Param("cartId")
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
	c.JSON(http.StatusCreated, gin.H{
		"cartId": cartId,
		"item":   item,
	})
}