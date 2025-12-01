package main

import (
	"context"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/zap"

	v1 "github.com/duynhne/monitoring/internal/cart/web/v1"
	v2 "github.com/duynhne/monitoring/internal/cart/web/v2"
	"github.com/duynhne/monitoring/pkg/middleware"
)

func main() {
	// Initialize structured logger
	logger, err := middleware.NewLogger()
	if err != nil {
		panic("Failed to initialize logger: " + err.Error())
	}
	defer logger.Sync()

	// Initialize OpenTelemetry tracing
	tp, err := middleware.InitTracing()
	if err != nil {
		logger.Warn("Failed to initialize tracing", zap.Error(err))
	} else {
		defer func() {
			if err := tp.Shutdown(context.Background()); err != nil {
				logger.Error("Error shutting down tracer provider", zap.Error(err))
			}
		}()
	}

	// Initialize Pyroscope profiling
	if err := middleware.InitProfiling(); err != nil {
		logger.Warn("Failed to initialize profiling", zap.Error(err))
	} else {
		defer middleware.StopProfiling()
	}

	r := gin.Default()

	// Tracing middleware (must be first for context propagation)
	r.Use(middleware.TracingMiddleware())

	// Logging middleware (must be before Prometheus middleware)
	r.Use(middleware.LoggingMiddleware(logger))

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
		apiV1.GET("/cart", v1.GetCart)
		apiV1.POST("/cart", v1.AddToCart)
	}

	// API v2
	apiV2 := r.Group("/api/v2")
	{
		apiV2.GET("/carts/:cartId", v2.GetCart)
		apiV2.POST("/carts/:cartId/items", v2.AddItem)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	logger.Info("Starting cart service", zap.String("port", port))
	if err := r.Run(":" + port); err != nil {
		logger.Fatal("Failed to start server", zap.Error(err))
	}
}
