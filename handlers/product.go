package handlers

import (
	"encoding/json"
	"math/rand"
	"net/http"
	"strconv"
	"sync"

	"github.com/gorilla/mux"
)

type Product struct {
	ID    int     `json:"id"`
	Name  string  `json:"name"`
	Price float64 `json:"price"`
	Stock int     `json:"stock"`
}

var (
	products   = make(map[int]*Product)
	productsMu sync.RWMutex
	nextProdID = 1
)

func init() {
	// Seed with some initial data
	products[1] = &Product{ID: 1, Name: "Laptop", Price: 999.99, Stock: 10}
	products[2] = &Product{ID: 2, Name: "Mouse", Price: 29.99, Stock: 50}
	products[3] = &Product{ID: 3, Name: "Keyboard", Price: 79.99, Stock: 30}
	nextProdID = 4
}

// GetProducts returns all products
func GetProducts(w http.ResponseWriter, r *http.Request) {
	// Simulate processing time (products query is faster)
	simulateProcessing(30, 100)

	productsMu.RLock()
	defer productsMu.RUnlock()

	productList := make([]*Product, 0, len(products))
	for _, product := range products {
		productList = append(productList, product)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(productList)
}

// GetProduct returns a single product by ID
func GetProduct(w http.ResponseWriter, r *http.Request) {
	// Simulate processing time
	simulateProcessing(20, 80)

	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		http.Error(w, "Invalid product ID", http.StatusBadRequest)
		return
	}

	productsMu.RLock()
	product, exists := products[id]
	productsMu.RUnlock()

	if !exists {
		http.Error(w, "Product not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(product)
}

// CreateProduct creates a new product
func CreateProduct(w http.ResponseWriter, r *http.Request) {
	// Simulate processing time (writes are slower)
	simulateProcessing(150, 400)

	// Randomly return server error (3% error rate)
	if rand.Float32() < 0.03 {
		http.Error(w, "Database connection error", http.StatusInternalServerError)
		return
	}

	var product Product
	if err := json.NewDecoder(r.Body).Decode(&product); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Validate product data
	if product.Name == "" {
		http.Error(w, "Product name is required", http.StatusBadRequest)
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

// UpdateProduct updates an existing product
func UpdateProduct(w http.ResponseWriter, r *http.Request) {
	// Simulate processing time
	simulateProcessing(120, 350)

	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		http.Error(w, "Invalid product ID", http.StatusBadRequest)
		return
	}

	var product Product
	if err := json.NewDecoder(r.Body).Decode(&product); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	productsMu.Lock()
	defer productsMu.Unlock()

	if _, exists := products[id]; !exists {
		http.Error(w, "Product not found", http.StatusNotFound)
		return
	}

	product.ID = id
	products[id] = &product

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(product)
}

// DeleteProduct deletes a product
func DeleteProduct(w http.ResponseWriter, r *http.Request) {
	// Simulate processing time
	simulateProcessing(80, 200)

	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		http.Error(w, "Invalid product ID", http.StatusBadRequest)
		return
	}

	productsMu.Lock()
	defer productsMu.Unlock()

	if _, exists := products[id]; !exists {
		http.Error(w, "Product not found", http.StatusNotFound)
		return
	}

	delete(products, id)
	w.WriteHeader(http.StatusNoContent)
}

