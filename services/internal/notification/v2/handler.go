package v2

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/demo/monitoring-golang/internal/notification/domain"
)

func ListNotifications(c *gin.Context) {
	notifications := []domain.Notification{
		{ID: "1", Type: "email", Message: "Welcome!", Status: "sent"},
		{ID: "2", Type: "sms", Message: "Order confirmed", Status: "delivered"},
	}
	c.JSON(http.StatusOK, notifications)
}

func GetNotification(c *gin.Context) {
	id := c.Param("id")
	notification := domain.Notification{
		ID:      id,
		Type:    "email",
		Message: "Notification details",
		Status:  "sent",
	}
	c.JSON(http.StatusOK, notification)
}