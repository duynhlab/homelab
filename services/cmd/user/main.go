package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	v1 "github.com/demo/monitoring-golang/internal/user/v1"
	v2 "github.com/demo/monitoring-golang/internal/user/v2"
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
		apiV1.GET("/users/:id", v1.GetUser)
		apiV1.GET("/users/profile", v1.GetProfile)
		apiV1.POST("/users", v1.CreateUser)
	}

	// API v2
	apiV2 := r.Group("/api/v2")
	{
		apiV2.GET("/users/:id", v2.GetUser)
		apiV2.GET("/users/profile", v2.GetProfile)
		apiV2.POST("/users", v2.CreateUser)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Starting user on :%s", port)
	log.Fatal(r.Run(":" + port))
}
