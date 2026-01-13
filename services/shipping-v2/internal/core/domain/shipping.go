package domain

// EstimateRequest represents a request to estimate shipping cost
type EstimateRequest struct {
	Origin      string  `json:"origin" binding:"required"`
	Destination string  `json:"destination" binding:"required"`
	Weight      float64 `json:"weight" binding:"required"`
}

// ShipmentEstimate represents a shipping cost estimate from the database
type ShipmentEstimate struct {
	ID            int     `json:"id"`
	Origin        string  `json:"origin"`
	Destination   string  `json:"destination"`
	Weight        float64 `json:"weight"`
	Cost          float64 `json:"cost"`
	EstimatedDays int     `json:"estimated_days"`
	Carrier       string  `json:"carrier,omitempty"`
}

// Shipment represents a shipment record
type Shipment struct {
	ID                int    `json:"id"`
	TrackingID        string `json:"tracking_id"`
	OrderID           *int   `json:"order_id,omitempty"`
	Status            string `json:"status"`
	Origin            string `json:"origin,omitempty"`
	Destination       string `json:"destination"`
	Carrier           string `json:"carrier,omitempty"`
	EstimatedDelivery string `json:"estimated_delivery,omitempty"`
	ActualDelivery    string `json:"actual_delivery,omitempty"`
}

// ShipmentTrackingHistory represents a tracking history entry
type ShipmentTrackingHistory struct {
	ID         int    `json:"id"`
	ShipmentID int    `json:"shipment_id"`
	Status     string `json:"status"`
	Location   string `json:"location,omitempty"`
	Notes      string `json:"notes,omitempty"`
}
