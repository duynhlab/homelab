package main

import (
	"context"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/zap"

	v1 "github.com/duynhne/monitoring/internal/user/web/v1"
	v2 "github.com/duynhne/monitoring/internal/user/web/v2"
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

	logger.Info("Starting user service", zap.String("port", port))
	if err := r.Run(":" + port); err != nil {
		logger.Fatal("Failed to start server", zap.Error(err))
	}
}
