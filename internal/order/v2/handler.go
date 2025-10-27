package v2

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/demo/monitoring-golang/internal/order/domain"
)

func ListOrders(c *gin.Context) {
	orders := []domain.Order{
		{ID: "1", Status: "pending", Items: []domain.OrderItem{{ProductID: "1", Quantity: 2, Price: 100}}, Total: 200},
		{ID: "2", Status: "shipped", Items: []domain.OrderItem{{ProductID: "2", Quantity: 1, Price: 150}}, Total: 150},
	}
	c.JSON(http.StatusOK, orders)
}

func GetOrderStatus(c *gin.Context) {
	orderId := c.Param("orderId")
	status := gin.H{
		"orderId": orderId,
		"status":  "shipped",
		"tracking": "TRK123456",
	}
	c.JSON(http.StatusOK, status)
}

func CreateOrder(c *gin.Context) {
	var req domain.CreateOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	order := domain.Order{
		ID:     "new-order-v2",
		Status: "pending",
		Items:  req.Items,
		Total:  300, // Mock calculation
	}
	c.JSON(http.StatusCreated, order)
}