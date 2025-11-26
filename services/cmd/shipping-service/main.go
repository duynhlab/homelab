package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	v1 "github.com/demo/monitoring-golang/internal/shipping/v1"
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
		apiV1.GET("/shipping/track", v1.TrackShipment)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Starting shipping-service on :%s", port)
	log.Fatal(r.Run(":" + port))
}
