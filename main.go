package main

import (
	"log"
	"net/http"
	"time"

	"github.com/demo/monitoring-golang/handlers"
	"github.com/demo/monitoring-golang/pkg/middleware"
	"github.com/gorilla/mux"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func main() {
	r := mux.NewRouter()

	// Apply Prometheus middleware to all routes
	r.Use(middleware.PrometheusMiddleware)

	// Health check endpoint
	r.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	}).Methods("GET")

	// API routes
	api := r.PathPrefix("/api").Subrouter()

	// User endpoints
	api.HandleFunc("/users", handlers.GetUsers).Methods("GET")
	api.HandleFunc("/users/{id}", handlers.GetUser).Methods("GET")
	api.HandleFunc("/users", handlers.CreateUser).Methods("POST")
	api.HandleFunc("/users/{id}", handlers.UpdateUser).Methods("PUT")
	api.HandleFunc("/users/{id}", handlers.DeleteUser).Methods("DELETE")

	// Product endpoints
	api.HandleFunc("/products", handlers.GetProducts).Methods("GET")
	api.HandleFunc("/products/{id}", handlers.GetProduct).Methods("GET")
	api.HandleFunc("/products", handlers.CreateProduct).Methods("POST")
	api.HandleFunc("/products/{id}", handlers.UpdateProduct).Methods("PUT")
	api.HandleFunc("/products/{id}", handlers.DeleteProduct).Methods("DELETE")

	// Checkout endpoints (v1)
	apiV1 := api.PathPrefix("/v1").Subrouter()
	apiV1.HandleFunc("/checkout", handlers.ProcessCheckout).Methods("POST")
	apiV1.HandleFunc("/checkout/{id}", handlers.GetCheckoutStatus).Methods("GET")

	// Order endpoints (v2)
	apiV2 := api.PathPrefix("/v2").Subrouter()
	apiV2.HandleFunc("/orders", handlers.GetOrders).Methods("GET")
	apiV2.HandleFunc("/orders/{id}", handlers.GetOrder).Methods("GET")
	apiV2.HandleFunc("/orders", handlers.CreateOrder).Methods("POST")
	apiV2.HandleFunc("/orders/{id}", handlers.UpdateOrder).Methods("PUT")
	apiV2.HandleFunc("/orders/{id}", handlers.DeleteOrder).Methods("DELETE")

	// V3 API endpoints (Next generation)
	apiV3 := api.PathPrefix("/v3").Subrouter()
	apiV3.HandleFunc("/users", handlers.GetUsersV3).Methods("GET")
	apiV3.HandleFunc("/users", handlers.CreateUserV3).Methods("POST")
	apiV3.HandleFunc("/products", handlers.GetProductsV3).Methods("GET")
	apiV3.HandleFunc("/products", handlers.CreateProductV3).Methods("POST")
	apiV3.HandleFunc("/checkout", handlers.ProcessCheckoutV3).Methods("POST")
	apiV3.HandleFunc("/orders", handlers.GetOrdersV3).Methods("GET")
	apiV3.HandleFunc("/orders", handlers.CreateOrderV3).Methods("POST")

	// Metrics endpoint (without middleware to avoid recursive metrics)
	r.Handle("/metrics", promhttp.Handler())

	// Create server with timeouts
	srv := &http.Server{
		Handler:      r,
		Addr:         ":8080",
		WriteTimeout: 15 * time.Second,
		ReadTimeout:  15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Println("🚀 Server starting on http://localhost:8080")
	log.Println("📊 Metrics available at http://localhost:8080/metrics")
	log.Println("🏥 Health check at http://localhost:8080/health")
	log.Println("📚 API endpoints:")
	log.Println("   Users & Products (v1):")
	log.Println("   - GET/POST   /api/users")
	log.Println("   - GET/POST   /api/products")
	log.Println("   Checkout (v1):")
	log.Println("   - POST       /api/v1/checkout")
	log.Println("   Orders (v2):")
	log.Println("   - GET/POST   /api/v2/orders")
	log.Println("   🆕 V3 API (Next Gen):")
	log.Println("   - GET/POST   /api/v3/users")
	log.Println("   - GET/POST   /api/v3/products")
	log.Println("   - POST       /api/v3/checkout")
	log.Println("   - GET/POST   /api/v3/orders")

	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}

