package v2

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/demo/monitoring-golang/internal/shipping/domain"
)

func EstimateShipment(c *gin.Context) {
	var req domain.EstimateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	estimate := gin.H{
		"origin":      req.Origin,
		"destination": req.Destination,
		"weight":      req.Weight,
		"cost":        25.99,
		"days":        3,
	}
	c.JSON(http.StatusOK, estimate)
}