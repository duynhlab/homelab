package v1

import (
	"context"
	"testing"
)

func TestEstimateShipping(t *testing.T) {
	service := NewShippingService()
	ctx := context.Background()

	tests := []struct {
		name        string
		origin      string
		destination string
		weight      float64
		wantCost    float64
		wantDays    int
		wantErr     bool
	}{
		{
			name:        "Same city, light package",
			origin:      "NY",
			destination: "NY",
			weight:      2.0,
			// Cost = 5.0 (base) + 2.0*1.5 (weight) + 0 (distance) = 8.0
			wantCost: 8.0,
			wantDays: 3,
			wantErr:  false,
		},
		{
			name:        "Different city, light package",
			origin:      "NY",
			destination: "CA",
			weight:      2.0,
			// Cost = 5.0 (base) + 2.0*1.5 (weight) + 10.0 (distance) = 18.0
			wantCost: 18.0,
			wantDays: 5,
			wantErr:  false,
		},
		{
			name:        "Same city, heavy package",
			origin:      "NY",
			destination: "NY",
			weight:      12.0,
			// Cost = 5.0 (base) + 12.0*1.5 (weight) + 0 (distance) = 23.0
			// Days = 3 + 2 (heavy penalty) = 5
			wantCost: 23.0,
			wantDays: 5,
			wantErr:  false,
		},
		{
			name:        "Different city, heavy package",
			origin:      "NY",
			destination: "CA",
			weight:      12.0,
			// Cost = 5.0 (base) + 12.0*1.5 (weight) + 10.0 (distance) = 33.0
			// Days = 5 + 2 (heavy penalty) = 7
			wantCost: 33.0,
			wantDays: 7,
			wantErr:  false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := service.EstimateShipping(ctx, tt.origin, tt.destination, tt.weight)
			if (err != nil) != tt.wantErr {
				t.Errorf("EstimateShipping() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if got.EstimatedCost != tt.wantCost {
				t.Errorf("EstimateShipping() cost = %v, want %v", got.EstimatedCost, tt.wantCost)
			}
			if got.EstimatedDays != tt.wantDays {
				t.Errorf("EstimateShipping() days = %v, want %v", got.EstimatedDays, tt.wantDays)
			}
		})
	}
}
