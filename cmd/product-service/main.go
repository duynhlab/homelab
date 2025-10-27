package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	v1 "github.com/demo/monitoring-golang/internal/product/v1"
	v2 "github.com/demo/monitoring-golang/internal/product/v2"
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
		apiV1.GET("/products", v1.ListProducts)
		apiV1.GET("/products/:id", v1.GetProduct)
		apiV1.POST("/products", v1.CreateProduct)
	}

	// API v2
	apiV2 := r.Group("/api/v2")
	{
		apiV2.GET("/catalog/items", v2.ListItems)
		apiV2.GET("/catalog/items/:itemId", v2.GetItem)
		apiV2.POST("/catalog/items", v2.CreateItem)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Starting product-service on :%s", port)
	log.Fatal(r.Run(":" + port))
}
