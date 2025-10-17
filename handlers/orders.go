package handlers

import (
	"encoding/json"
	"math/rand"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/mux"
)

type Order struct {
	ID         string   `json:"id"`
	UserID     string   `json:"user_id"`
	Items      []string `json:"items"`
	TotalPrice float64  `json:"total_price"`
	Status     string   `json:"status"`
	CreatedAt  string   `json:"created_at"`
}

var (
	orders   = make(map[string]Order)
	ordersMu sync.RWMutex
)

// GetOrders handles GET /api/v2/orders
func GetOrders(w http.ResponseWriter, r *http.Request) {
	// Simulate database query time (100-300ms)
	time.Sleep(time.Duration(100+rand.Intn(200)) * time.Millisecond)

	ordersMu.RLock()
	orderList := make([]Order, 0, len(orders))
	for _, order := range orders {
		orderList = append(orderList, order)
	}
	ordersMu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(orderList)
}

// GetOrder handles GET /api/v2/orders/{id}
func GetOrder(w http.ResponseWriter, r *http.Request) {
	// Simulate database lookup (50-150ms)
	time.Sleep(time.Duration(50+rand.Intn(100)) * time.Millisecond)

	vars := mux.Vars(r)
	id := vars["id"]

	order, exists := orders[id]
	if !exists {
		http.Error(w, "Order not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(order)
}

// CreateOrder handles POST /api/v2/orders
func CreateOrder(w http.ResponseWriter, r *http.Request) {
	// Simulate order creation time (150-400ms)
	time.Sleep(time.Duration(150+rand.Intn(250)) * time.Millisecond)

	var order Order
	if err := json.NewDecoder(r.Body).Decode(&order); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Simulate occasional validation errors (3% failure rate)
	if rand.Float32() < 0.03 {
		http.Error(w, "Invalid order data", http.StatusBadRequest)
		return
	}

	order.ID = generateID("ORD")
	order.Status = "pending"
	order.CreatedAt = time.Now().Format(time.RFC3339)
	
	ordersMu.Lock()
	orders[order.ID] = order
	ordersMu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(order)
}

// UpdateOrder handles PUT /api/v2/orders/{id}
func UpdateOrder(w http.ResponseWriter, r *http.Request) {
	// Simulate update operation (100-250ms)
	time.Sleep(time.Duration(100+rand.Intn(150)) * time.Millisecond)

	vars := mux.Vars(r)
	id := vars["id"]

	order, exists := orders[id]
	if !exists {
		http.Error(w, "Order not found", http.StatusNotFound)
		return
	}

	var updates Order
	if err := json.NewDecoder(r.Body).Decode(&updates); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Update order
	order.Status = updates.Status
	if updates.TotalPrice > 0 {
		order.TotalPrice = updates.TotalPrice
	}
	orders[id] = order

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(order)
}

// DeleteOrder handles DELETE /api/v2/orders/{id}
func DeleteOrder(w http.ResponseWriter, r *http.Request) {
	// Simulate delete operation (50-150ms)
	time.Sleep(time.Duration(50+rand.Intn(100)) * time.Millisecond)

	vars := mux.Vars(r)
	id := vars["id"]

	if _, exists := orders[id]; !exists {
		http.Error(w, "Order not found", http.StatusNotFound)
		return
	}

	delete(orders, id)
	w.WriteHeader(http.StatusNoContent)
}

// Helper function to generate IDs (reuse from other handlers)
func generateID(prefix string) string {
	if prefix == "" {
		return time.Now().Format("20060102150405")
	}
	return prefix + "-" + time.Now().Format("20060102150405")
}

