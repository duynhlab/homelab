package main

import (
	"context"
	"log/slog"
	"net/http"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/duynhne/monitoring/services/pkg/logger/clog"
	"github.com/duynhne/monitoring/services/cart/config"
	database "github.com/duynhne/monitoring/services/cart/internal/core"
	"github.com/duynhne/monitoring/services/cart/internal/core/repository"
	logicv1 "github.com/duynhne/monitoring/services/cart/internal/logic/v1"
	v1 "github.com/duynhne/monitoring/services/cart/internal/web/v1"
	"github.com/duynhne/monitoring/services/cart/middleware"
)

func main() {
	// Load configuration from environment variables (with .env file support for local dev)
	cfg := config.Load()
	if err := cfg.Validate(); err != nil {
		panic("Configuration validation failed: " + err.Error())
	}

	// Initialize structured logger (clog/slog) with LOG_LEVEL from config
	clog.Setup(cfg.Logging.Level)
	// slog.Default() is now configured with JSON handler and trace injection

	slog.Info("Service starting",
		"service", cfg.Service.Name,
		"version", cfg.Service.Version,
		"env", cfg.Service.Env,
		"port", cfg.Service.Port,
	)

	// Initialize OpenTelemetry tracing with centralized config
	var tp interface{ Shutdown(context.Context) error }
	var err error
	if cfg.Tracing.Enabled {
		tp, err = middleware.InitTracing(cfg)
		if err != nil {
			slog.Warn("Failed to initialize tracing", "error", err)
		} else {
			slog.Info("Tracing initialized",
				"endpoint", cfg.Tracing.Endpoint,
				"sample_rate", cfg.Tracing.SampleRate,
			)
		}
	} else {
		slog.Info("Tracing disabled (TRACING_ENABLED=false)")
	}

	// Initialize Pyroscope profiling
	if cfg.Profiling.Enabled {
		if err := middleware.InitProfiling(); err != nil {
			slog.Warn("Failed to initialize profiling", "error", err)
		} else {
			slog.Info("Profiling initialized",
				"endpoint", cfg.Profiling.Endpoint,
			)
			defer middleware.StopProfiling()
		}
	} else {
		slog.Info("Profiling disabled (PROFILING_ENABLED=false)")
	}

	// Initialize database connection pool (pgx)
	pool, err := database.Connect(context.Background())
	if err != nil {
		slog.Error("Failed to connect to database", "error", err)
		// Fatal replacement
		panic(err)
	}
	defer pool.Close()
	slog.Info("Database connection pool established")

	// Initialize repositories (Core layer)
	cartRepo := repository.NewPostgresCartRepository(pool)
	slog.Info("Cart repository initialized")

	// Initialize services (Logic layer) with dependency injection
	cartService := logicv1.NewCartService(cartRepo)
	slog.Info("Cart service initialized")

	// Set service instances in Web handlers
	v1.SetCartService(cartService)
	slog.Info("Web handlers configured")

	// Initialize auth client for token introspection
	authClient := middleware.NewAuthClient(cfg.AuthServiceURL)
	slog.Info("Auth client initialized", "auth_service_url", cfg.AuthServiceURL)

	r := gin.Default()

	var isShuttingDown atomic.Bool

	// Tracing middleware (must be first for context propagation)
	r.Use(middleware.TracingMiddleware())

	// Logging middleware (must be before Prometheus middleware)
	r.Use(middleware.LoggingMiddleware())

	// Prometheus middleware
	r.Use(middleware.PrometheusMiddleware())

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	// Readiness check
	// Returns 503 once shutdown has started, to drain traffic before HTTP shutdown.
	r.GET("/ready", func(c *gin.Context) {
		if isShuttingDown.Load() {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "shutting_down"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// Metrics endpoint
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// API v1 with auth middleware (canonical API - frontend-aligned)
	apiV1 := r.Group("/api/v1")
	apiV1.Use(middleware.AuthMiddleware(authClient))
	{
		apiV1.GET("/cart", v1.GetCart)
		apiV1.POST("/cart", v1.AddToCart)
		apiV1.DELETE("/cart", v1.ClearCart)
		apiV1.GET("/cart/count", v1.GetCartCount)
		apiV1.PATCH("/cart/items/:itemId", v1.UpdateCartItem)
		apiV1.DELETE("/cart/items/:itemId", v1.RemoveCartItem)
	}

	// Create HTTP server
	srv := &http.Server{
		Addr:    ":" + cfg.Service.Port,
		Handler: r,
	}

	// Start server in a goroutine
	go func() {
		slog.Info("Starting cart service", "port", cfg.Service.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("Failed to start server", "error", err)
			panic(err)
		}
	}()

	// Graceful shutdown - modern signal handling with context
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	// Wait for shutdown signal
	<-ctx.Done()
	slog.Info("Shutdown signal received")

	// Fail readiness first and wait for propagation (best practice for K8s rollout).
	isShuttingDown.Store(true)
	drainDelay := cfg.GetReadinessDrainDelayDuration()
	if drainDelay > 0 {
		slog.Info("Readiness drain delay started", "delay", drainDelay)
		time.Sleep(drainDelay)
		slog.Info("Readiness drain delay completed", "delay", drainDelay)
	}

	// Shutdown context with configurable timeout
	shutdownTimeout := cfg.GetShutdownTimeoutDuration()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	slog.Info("Shutting down server...", "timeout", shutdownTimeout)

	// Explicit cleanup sequence: HTTP Server → Database → Tracer
	// This ensures predictable shutdown order and easier debugging

	// 1. Shutdown HTTP server (stop accepting new connections, wait for in-flight requests)
	if err := srv.Shutdown(shutdownCtx); err != nil {
		slog.Error("HTTP server shutdown error", "error", err)
	} else {
		slog.Info("HTTP server shutdown complete")
	}

	// 2. Close database connections (explicit cleanup + defer for safety)
	pool.Close()
	slog.Info("Database pool closed")

	// 3. Shutdown tracer (flush pending spans)
	if tp != nil {
		if err := tp.Shutdown(shutdownCtx); err != nil {
			slog.Error("Tracer shutdown error", "error", err)
		} else {
			slog.Info("Tracer shutdown complete")
		}
	}

	slog.Info("Graceful shutdown complete")
}
