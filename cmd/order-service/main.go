package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	v1 "github.com/demo/monitoring-golang/internal/order/v1"
	v2 "github.com/demo/monitoring-golang/internal/order/v2"
	"github.com/demo/monitoring-golang/pkg/middleware"
)

func main() {
	r := gin.Default()

	// Prometheus middleware
	r.Use(middleware.PrometheusMiddleware())

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	// Metrics endpoint
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// API v1
	apiV1 := r.Group("/api/v1")
	{
		apiV1.GET("/orders", v1.ListOrders)
		apiV1.GET("/orders/:id", v1.GetOrder)
		apiV1.POST("/orders", v1.CreateOrder)
	}

	// API v2
	apiV2 := r.Group("/api/v2")
	{
		apiV2.GET("/orders", v2.ListOrders)
		apiV2.GET("/orders/:orderId/status", v2.GetOrderStatus)
		apiV2.POST("/orders", v2.CreateOrder)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Starting order-service on :%s", port)
	log.Fatal(r.Run(":" + port))
}
