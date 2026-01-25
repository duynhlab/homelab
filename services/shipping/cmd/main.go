package main

import (
	"context"
	"net/http"
	"os/signal"
	"syscall"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/zap"

	"github.com/duynhne/monitoring/services/shipping/config"
	database "github.com/duynhne/monitoring/services/shipping/internal/core"
	v1 "github.com/duynhne/monitoring/services/shipping/internal/web/v1"
	"github.com/duynhne/monitoring/services/shipping/middleware"
)

func main() {
	// Load configuration from environment variables (with .env file support for local dev)
	cfg := config.Load()
	if err := cfg.Validate(); err != nil {
		panic("Configuration validation failed: " + err.Error())
	}

	// Initialize structured logger
	logger, err := middleware.NewLogger()
	if err != nil {
		panic("Failed to initialize logger: " + err.Error())
	}
	defer logger.Sync()

	logger.Info("Service starting",
		zap.String("service", cfg.Service.Name),
		zap.String("version", cfg.Service.Version),
		zap.String("env", cfg.Service.Env),
		zap.String("port", cfg.Service.Port),
	)

	// Initialize database connection pool (pgx)
	pool, err := database.Connect(context.Background())
	if err != nil {
		logger.Fatal("Failed to connect to database", zap.Error(err))
	}
	defer pool.Close()
	logger.Info("Database connection pool established")

	// Initialize OpenTelemetry tracing with centralized config
	var tp interface{ Shutdown(context.Context) error }
	if cfg.Tracing.Enabled {
		tp, err = middleware.InitTracing(cfg)
		if err != nil {
			logger.Warn("Failed to initialize tracing", zap.Error(err))
		} else {
			logger.Info("Tracing initialized",
				zap.String("endpoint", cfg.Tracing.Endpoint),
				zap.Float64("sample_rate", cfg.Tracing.SampleRate),
			)
		}
	} else {
		logger.Info("Tracing disabled (TRACING_ENABLED=false)")
	}

	// Initialize Pyroscope profiling
	if cfg.Profiling.Enabled {
		if err := middleware.InitProfiling(); err != nil {
			logger.Warn("Failed to initialize profiling", zap.Error(err))
		} else {
			logger.Info("Profiling initialized",
				zap.String("endpoint", cfg.Profiling.Endpoint),
			)
			defer middleware.StopProfiling()
		}
	} else {
		logger.Info("Profiling disabled (PROFILING_ENABLED=false)")
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

	// API v1 (shipping service only has v1)
	apiV1 := r.Group("/api/v1")
	{
		apiV1.GET("/shipping/track", v1.TrackShipment)
		apiV1.GET("/shipping/estimate", v1.EstimateShipping)
		apiV1.GET("/shipping/orders/:orderId", v1.GetShipmentByOrder)
	}

	// Create HTTP server
	srv := &http.Server{
		Addr:    ":" + cfg.Service.Port,
		Handler: r,
	}

	// Start server in a goroutine
	go func() {
		logger.Info("Starting shipping service", zap.String("port", cfg.Service.Port))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("Failed to start server", zap.Error(err))
		}
	}()

	// Graceful shutdown - modern signal handling with context
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	// Wait for shutdown signal
	<-ctx.Done()
	logger.Info("Shutdown signal received")

	// Shutdown context with configurable timeout
	shutdownTimeout := cfg.GetShutdownTimeoutDuration()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	logger.Info("Shutting down server...", zap.Duration("timeout", shutdownTimeout))

	// Explicit cleanup sequence: HTTP Server → Database → Tracer
	// This ensures predictable shutdown order and easier debugging

	// 1. Shutdown HTTP server (stop accepting new connections, wait for in-flight requests)
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("HTTP server shutdown error", zap.Error(err))
	} else {
		logger.Info("HTTP server shutdown complete")
	}

	// 2. Close database connections (explicit cleanup + defer for safety)
	pool.Close()
	logger.Info("Database pool closed")

	// 3. Shutdown tracer (flush pending spans)
	if tp != nil {
		if err := tp.Shutdown(shutdownCtx); err != nil {
			logger.Error("Tracer shutdown error", zap.Error(err))
		} else {
			logger.Info("Tracer shutdown complete")
		}
	}

	logger.Info("Graceful shutdown complete")
}
