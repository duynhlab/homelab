package v1

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/demo/monitoring-golang/internal/shipping/domain"
)

func TrackShipment(c *gin.Context) {
	trackingID := c.Query("trackingId")
	shipment := domain.Shipment{
		ID:          "1",
		TrackingID:  trackingID,
		Status:      "in_transit",
		Destination: "New York",
	}
	c.JSON(http.StatusOK, shipment)
}