package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	v1 "github.com/demo/monitoring-golang/internal/auth/v1"
	v2 "github.com/demo/monitoring-golang/internal/auth/v2"
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
		apiV1.POST("/auth/login", v1.Login)
		apiV1.POST("/auth/register", v1.Register)
	}

	// API v2
	apiV2 := r.Group("/api/v2")
	{
		apiV2.POST("/auth/login", v2.Login)
		apiV2.POST("/auth/register", v2.Register)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Starting auth-service on :%s", port)
	log.Fatal(r.Run(":" + port))
}
