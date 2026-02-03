package main

import (
	"context"
	"net/http"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/zap"

	"github.com/duynhne/monitoring/services/order/config"
	database "github.com/duynhne/monitoring/services/order/internal/core"
	"github.com/duynhne/monitoring/services/order/internal/core/repository"
	logicv1 "github.com/duynhne/monitoring/services/order/internal/logic/v1"
	v1 "github.com/duynhne/monitoring/services/order/internal/web/v1"
	"github.com/duynhne/monitoring/services/order/middleware"
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

	// Initialize database connection pool (pgx)
	pool, err := database.Connect(context.Background())
	if err != nil {
		logger.Fatal("Failed to connect to database", zap.Error(err))
	}
	defer pool.Close()
	logger.Info("Database connection pool established")

	// Initialize repositories (Core layer)
	orderRepo := repository.NewPostgresOrderRepository(pool)
	txManager := repository.NewPostgresTransactionManager(pool)
	logger.Info("Order repository and transaction manager initialized")

	// Initialize services (Logic layer) with dependency injection
	orderService := logicv1.NewOrderService(orderRepo, txManager)
	logger.Info("Order service initialized")

	// Initialize auth client for token introspection
	authClient := middleware.NewAuthClient(cfg.AuthServiceURL)
	logger.Info("Auth client initialized", zap.String("auth_service_url", cfg.AuthServiceURL))

	// Initialize shipping client for order aggregation
	shippingClient := v1.NewShippingClient(cfg.ShippingServiceURL)
	v1.SetShippingClient(shippingClient)
	logger.Info("Shipping client initialized", zap.String("shipping_service_url", cfg.ShippingServiceURL))

	// Initialize cart client for best-effort cart clearing after order creation
	cartClient := v1.NewCartClient(cfg.CartServiceURL)
	v1.SetCartClient(cartClient)
	logger.Info("Cart client initialized", zap.String("cart_service_url", cfg.CartServiceURL))

	r := gin.Default()

	var isShuttingDown atomic.Bool

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

	// Inject service into v1 handler
	v1.SetOrderService(orderService)

	// API v1 with auth middleware (canonical API - frontend-aligned)
	apiV1 := r.Group("/api/v1")
	apiV1.Use(middleware.AuthMiddleware(authClient, logger, cfg.AuthAllowUnauthenticatedFallback))
	{
		apiV1.GET("/orders", v1.ListOrders)
		apiV1.GET("/orders/:id", v1.GetOrder)
		apiV1.GET("/orders/:id/details", v1.GetOrderDetails) // Aggregation endpoint with shipment
		apiV1.POST("/orders", v1.CreateOrder)
	}

	// Create HTTP server
	srv := &http.Server{
		Addr:    ":" + cfg.Service.Port,
		Handler: r,
	}

	// Start server in a goroutine
	go func() {
		logger.Info("Starting order service", zap.String("port", cfg.Service.Port))
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

	// Fail readiness first and wait for propagation (best practice for K8s rollout).
	isShuttingDown.Store(true)
	drainDelay := cfg.GetReadinessDrainDelayDuration()
	if drainDelay > 0 {
		logger.Info("Readiness drain delay started", zap.Duration("delay", drainDelay))
		time.Sleep(drainDelay)
		logger.Info("Readiness drain delay completed", zap.Duration("delay", drainDelay))
	}

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
