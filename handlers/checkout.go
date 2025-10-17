package handlers

import (
	"encoding/json"
	"math/rand"
	"net/http"
	"time"
)

type CheckoutRequest struct {
	UserID    string  `json:"user_id"`
	ProductID string  `json:"product_id"`
	Quantity  int     `json:"quantity"`
	Amount    float64 `json:"amount"`
}

type CheckoutResponse struct {
	TransactionID string  `json:"transaction_id"`
	Status        string  `json:"status"`
	Amount        float64 `json:"amount"`
	Timestamp     string  `json:"timestamp"`
}

// ProcessCheckout handles POST /api/v1/checkout
func ProcessCheckout(w http.ResponseWriter, r *http.Request) {
	// Simulate processing time (longer for checkout - 200-800ms)
	time.Sleep(time.Duration(200+rand.Intn(600)) * time.Millisecond)

	var req CheckoutRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Simulate occasional errors (5% failure rate)
	if rand.Float32() < 0.05 {
		http.Error(w, "Payment processing failed", http.StatusInternalServerError)
		return
	}

	// Generate transaction ID
	transactionID := generateID("TXN")

	response := CheckoutResponse{
		TransactionID: transactionID,
		Status:        "completed",
		Amount:        req.Amount,
		Timestamp:     time.Now().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// GetCheckoutStatus handles GET /api/v1/checkout/{id}
func GetCheckoutStatus(w http.ResponseWriter, r *http.Request) {
	// Simulate faster read operation (50-200ms)
	time.Sleep(time.Duration(50+rand.Intn(150)) * time.Millisecond)

	response := CheckoutResponse{
		TransactionID: "TXN-" + generateID(""),
		Status:        "completed",
		Amount:        99.99,
		Timestamp:     time.Now().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

