package domain

type Shipment struct {
	ID          string `json:"id"`
	TrackingID  string `json:"trackingId"`
	Status      string `json:"status"`
	Destination string `json:"destination"`
}

type EstimateRequest struct {
	Origin      string `json:"origin" binding:"required"`
	Destination string `json:"destination" binding:"required"`
	Weight      float64 `json:"weight" binding:"required"`
}