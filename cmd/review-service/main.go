package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	v1 "github.com/demo/monitoring-golang/internal/review/v1"
	v2 "github.com/demo/monitoring-golang/internal/review/v2"
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
		apiV1.GET("/reviews", v1.ListReviews)
		apiV1.POST("/reviews", v1.CreateReview)
	}

	// API v2
	apiV2 := r.Group("/api/v2")
	{
		apiV2.GET("/reviews/:reviewId", v2.GetReview)
		apiV2.POST("/reviews", v2.CreateReview)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Starting review-service on :%s", port)
	log.Fatal(r.Run(":" + port))
}
