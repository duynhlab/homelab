package handlers

import (
	"encoding/json"
	"math/rand"
	"net/http"
	"time"
)

// V3 API - Next generation endpoints with enhanced features

// GetUsersV3 handles GET /api/v3/users
func GetUsersV3(w http.ResponseWriter, r *http.Request) {
	time.Sleep(time.Duration(50+rand.Intn(100)) * time.Millisecond)
	
	usersMu.RLock()
	defer usersMu.RUnlock()
	
	userList := make([]*User, 0, len(users))
	for _, user := range users {
		userList = append(userList, user)
	}
	
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(userList)
}

// CreateUserV3 handles POST /api/v3/users
func CreateUserV3(w http.ResponseWriter, r *http.Request) {
	time.Sleep(time.Duration(80+rand.Intn(120)) * time.Millisecond)
	
	var user User
	if err := json.NewDecoder(r.Body).Decode(&user); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	
	if rand.Float32() < 0.02 {
		http.Error(w, "V3 validation error", http.StatusBadRequest)
		return
	}
	
	usersMu.Lock()
	user.ID = nextID
	nextID++
	users[user.ID] = &user
	usersMu.Unlock()
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(user)
}

// GetProductsV3 handles GET /api/v3/products
func GetProductsV3(w http.ResponseWriter, r *http.Request) {
	time.Sleep(time.Duration(60+rand.Intn(110)) * time.Millisecond)
	
	productsMu.RLock()
	defer productsMu.RUnlock()
	
	productList := make([]*Product, 0, len(products))
	for _, product := range products {
		productList = append(productList, product)
	}
	
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(productList)
}

// CreateProductV3 handles POST /api/v3/products
func CreateProductV3(w http.ResponseWriter, r *http.Request) {
	time.Sleep(time.Duration(90+rand.Intn(130)) * time.Millisecond)
	
	var product Product
	if err := json.NewDecoder(r.Body).Decode(&product); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	
	if rand.Float32() < 0.02 {
		http.Error(w, "V3 product validation error", http.StatusBadRequest)
		return
	}
	
	productsMu.Lock()
	product.ID = nextProdID
	nextProdID++
	products[product.ID] = &product
	productsMu.Unlock()
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(product)
}

// ProcessCheckoutV3 handles POST /api/v3/checkout
func ProcessCheckoutV3(w http.ResponseWriter, r *http.Request) {
	time.Sleep(time.Duration(150+rand.Intn(500)) * time.Millisecond)
	
	var req CheckoutRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	
	if rand.Float32() < 0.04 {
		http.Error(w, "V3 payment processing failed", http.StatusInternalServerError)
		return
	}
	
	response := CheckoutResponse{
		TransactionID: "V3-TXN-" + generateID(""),
		Status:        "completed",
		Amount:        req.Amount,
		Timestamp:     time.Now().Format(time.RFC3339),
	}
	
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// GetOrdersV3 handles GET /api/v3/orders
func GetOrdersV3(w http.ResponseWriter, r *http.Request) {
	time.Sleep(time.Duration(80+rand.Intn(180)) * time.Millisecond)
	
	ordersMu.RLock()
	orderList := make([]Order, 0, len(orders))
	for _, order := range orders {
		orderList = append(orderList, order)
	}
	ordersMu.RUnlock()
	
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(orderList)
}

// CreateOrderV3 handles POST /api/v3/orders
func CreateOrderV3(w http.ResponseWriter, r *http.Request) {
	time.Sleep(time.Duration(120+rand.Intn(230)) * time.Millisecond)
	
	var order Order
	if err := json.NewDecoder(r.Body).Decode(&order); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	
	if rand.Float32() < 0.03 {
		http.Error(w, "V3 order validation failed", http.StatusBadRequest)
		return
	}
	
	order.ID = "V3-ORD-" + generateID("")
	order.Status = "pending"
	order.CreatedAt = time.Now().Format(time.RFC3339)
	
	ordersMu.Lock()
	orders[order.ID] = order
	ordersMu.Unlock()
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(order)
}

