package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.uber.org/zap"

	v1 "github.com/duynhne/monitoring/internal/auth/web/v1"
	v2 "github.com/duynhne/monitoring/internal/auth/web/v2"
	"github.com/duynhne/monitoring/pkg/config"
	"github.com/duynhne/monitoring/pkg/middleware"
)

func main() {
	// Load configuration from environment variables (with .env file support for local dev)
	// Priority: .env file < environment variables < Helm values (via extraEnv)
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
	// Tracing config: TRACING_ENABLED, OTEL_COLLECTOR_ENDPOINT, OTEL_SAMPLE_RATE
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
	// Profiling config: PROFILING_ENABLED, PYROSCOPE_ENDPOINT
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

	// Create HTTP server
	srv := &http.Server{
		Addr:    ":" + cfg.Service.Port,
		Handler: r,
	}

	// Start server in a goroutine
	go func() {
		logger.Info("Starting auth service", zap.String("port", cfg.Service.Port))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("Failed to start server", zap.Error(err))
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("Shutting down server...")

	// Shutdown context with timeout
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Go 1.25 WaitGroup.Go() for parallel shutdown (commented for now - use when Go 1.25 is available)
	// var wg sync.WaitGroup
	// wg.Go(func() {
	// 	if tp != nil {
	// 		if err := tp.Shutdown(shutdownCtx); err != nil {
	// 			logger.Error("Error shutting down tracer", zap.Error(err))
	// 		}
	// 	}
	// })
	// wg.Go(func() {
	// 	if err := srv.Shutdown(shutdownCtx); err != nil {
	// 		logger.Error("Server forced to shutdown", zap.Error(err))
	// 	}
	// })
	// wg.Wait()

	// Sequential shutdown (current approach - works with Go 1.23)
	var wg sync.WaitGroup

	// Shutdown tracing (flush pending spans)
	if tp != nil {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := tp.Shutdown(shutdownCtx); err != nil {
				logger.Error("Error shutting down tracer", zap.Error(err))
			} else {
				logger.Info("Tracer shutdown complete")
			}
		}()
	}

	// Shutdown HTTP server
	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			logger.Error("Server forced to shutdown", zap.Error(err))
		} else {
			logger.Info("HTTP server shutdown complete")
		}
	}()

	wg.Wait()
	logger.Info("Server exited gracefully")
}
