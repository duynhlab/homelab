package main

import (
	"context"
	"net/http"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/zap"

	"github.com/duynhne/monitoring/services/product/config"
	database "github.com/duynhne/monitoring/services/product/internal/core"
	"github.com/duynhne/monitoring/services/product/internal/core/cache"
	"github.com/duynhne/monitoring/services/product/internal/core/repository"
	logicv1 "github.com/duynhne/monitoring/services/product/internal/logic/v1"
	v1 "github.com/duynhne/monitoring/services/product/internal/web/v1"
	"github.com/duynhne/monitoring/services/product/middleware"
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
	productRepo := repository.NewPostgresProductRepository(pool)
	logger.Info("Product repository initialized")

	// Initialize cache client (Core layer) - optional, can be nil if disabled
	var productCache *cache.ProductCache
	if cfg.Cache.Enabled {
		cacheAddr := cfg.Cache.Host + ":" + cfg.Cache.Port
		cacheClient, err := cache.NewValkeyCacheClient(cacheAddr, cfg.Cache.Password, cfg.Cache.DB)
		if err != nil {
			logger.Warn("Failed to initialize cache client, continuing without cache",
				zap.Error(err),
				zap.String("cache_addr", cacheAddr),
			)
		} else {
			productCache = cache.NewProductCache(cacheClient, cfg.Cache.TTLProductList, cfg.Cache.TTLProductDetail)
			logger.Info("Cache client initialized",
				zap.String("cache_addr", cacheAddr),
				zap.Duration("ttl_list", cfg.Cache.TTLProductList),
				zap.Duration("ttl_detail", cfg.Cache.TTLProductDetail),
			)
			defer func() {
				if err := cacheClient.Close(); err != nil {
					logger.Error("Failed to close cache client", zap.Error(err))
				} else {
					logger.Info("Cache client closed")
				}
			}()
		}
	} else {
		logger.Info("Cache disabled (CACHE_ENABLED=false)")
	}

	// Initialize services (Logic layer) with dependency injection
	productService := logicv1.NewProductService(productRepo, productCache)
	logger.Info("Product service initialized")

	// Set service instances in Web handlers
	v1.SetProductService(productService)

	// Initialize review service client for aggregation in product details endpoint
	reviewClient := v1.NewReviewClient(cfg.ReviewServiceURL)
	v1.SetReviewClient(reviewClient)
	logger.Info("Review client initialized", zap.String("review_service_url", cfg.ReviewServiceURL))

	logger.Info("Web handlers configured")

	r := gin.Default()

	var isShuttingDown atomic.Bool

	// CORS middleware (must be before other middleware for OPTIONS requests)
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"http://localhost:3000", "http://localhost:3001"},
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

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

	// API v1 (canonical API - frontend-aligned)
	apiV1 := r.Group("/api/v1")
	{
		apiV1.GET("/products", v1.ListProducts)
		apiV1.GET("/products/:id", v1.GetProduct)
		apiV1.GET("/products/:id/details", v1.GetProductDetails) // Aggregation endpoint
		apiV1.POST("/products", v1.CreateProduct)
	}

	// Create HTTP server
	srv := &http.Server{
		Addr:    ":" + cfg.Service.Port,
		Handler: r,
	}

	// Start server in a goroutine
	go func() {
		logger.Info("Starting product service", zap.String("port", cfg.Service.Port))
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

	// Explicit cleanup sequence: HTTP Server → Cache → Database → Tracer
	// This ensures predictable shutdown order and easier debugging

	// 1. Shutdown HTTP server (stop accepting new connections, wait for in-flight requests)
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("HTTP server shutdown error", zap.Error(err))
	} else {
		logger.Info("HTTP server shutdown complete")
	}

	// 2. Close cache connection (if enabled)
	// Note: Cache client cleanup is handled by defer in initialization section above

	// 3. Close database connections (explicit cleanup + defer for safety)
	pool.Close()
	logger.Info("Database pool closed")

	// 4. Shutdown tracer (flush pending spans)
	if tp != nil {
		if err := tp.Shutdown(shutdownCtx); err != nil {
			logger.Error("Tracer shutdown error", zap.Error(err))
		} else {
			logger.Info("Tracer shutdown complete")
		}
	}

	logger.Info("Graceful shutdown complete")
}
