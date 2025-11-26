package v1

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/demo/monitoring-golang/internal/notification/domain"
)

func SendEmail(c *gin.Context) {
	var req domain.SendEmailRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	notification := domain.Notification{
		ID:      "email-1",
		Type:    "email",
		Message: req.Subject,
		Status:  "sent",
	}
	c.JSON(http.StatusOK, notification)
}

func SendSMS(c *gin.Context) {
	var req domain.SendSMSRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	notification := domain.Notification{
		ID:      "sms-1",
		Type:    "sms",
		Message: req.Message,
		Status:  "sent",
	}
	c.JSON(http.StatusOK, notification)
}