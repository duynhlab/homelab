package main

import (
	"context"
	"net/http"
	"os/signal"
	"syscall"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/rs/zerolog/log"

	"github.com/duynhne/monitoring/services/pkg/logger/zerolog"
	"github.com/duynhne/monitoring/services/auth/config"
	database "github.com/duynhne/monitoring/services/auth/internal/core"
	v1 "github.com/duynhne/monitoring/services/auth/internal/web/v1"
	"github.com/duynhne/monitoring/services/auth/middleware"
)

func main() {
	// Load configuration
	cfg := config.Load()
	if err := cfg.Validate(); err != nil {
		panic("Configuration validation failed: " + err.Error())
	}

	// Initialize Zerolog
	zerolog.Setup()

	log.Info().
		Str("service", cfg.Service.Name).
		Str("version", cfg.Service.Version).
		Str("env", cfg.Service.Env).
		Str("port", cfg.Service.Port).
		Msg("Service starting")

	// Initialize OpenTelemetry tracing
	var tp interface{ Shutdown(context.Context) error }
	var err error
	if cfg.Tracing.Enabled {
		tp, err = middleware.InitTracing(cfg)
		if err != nil {
			log.Warn().Err(err).Msg("Failed to initialize tracing")
		} else {
			log.Info().
				Str("endpoint", cfg.Tracing.Endpoint).
				Float64("sample_rate", cfg.Tracing.SampleRate).
				Msg("Tracing initialized")
		}
	} else {
		log.Info().Msg("Tracing disabled (TRACING_ENABLED=false)")
	}

	// Initialize Pyroscope profiling
	if cfg.Profiling.Enabled {
		if err := middleware.InitProfiling(); err != nil {
			log.Warn().Err(err).Msg("Failed to initialize profiling")
		} else {
			log.Info().
				Str("endpoint", cfg.Profiling.Endpoint).
				Msg("Profiling initialized")
			defer middleware.StopProfiling()
		}
	} else {
		log.Info().Msg("Profiling disabled (PROFILING_ENABLED=false)")
	}

	// Initialize database connection pool (pgx)
	pool, err := database.Connect(context.Background())
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to connect to database")
	}
	defer pool.Close()
	log.Info().Msg("Database connection pool established")

	r := gin.Default()

	// Tracing middleware
	r.Use(middleware.TracingMiddleware())

	// Logging middleware
	r.Use(middleware.LoggingMiddleware())

	// Prometheus middleware
	r.Use(middleware.PrometheusMiddleware())

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	// Metrics endpoint
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// API v1 (canonical API - frontend-aligned)
	apiV1 := r.Group("/api/v1")
	{
		apiV1.POST("/auth/login", v1.Login)
		apiV1.POST("/auth/register", v1.Register)
		apiV1.GET("/auth/me", v1.GetMe)
	}

	// Create HTTP server
	srv := &http.Server{
		Addr:    ":" + cfg.Service.Port,
		Handler: r,
	}

	// Start server in a goroutine
	go func() {
		log.Info().Str("port", cfg.Service.Port).Msg("Starting auth service")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal().Err(err).Msg("Failed to start server")
		}
	}()

	// Graceful shutdown
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	// Wait for shutdown signal
	<-ctx.Done()
	log.Info().Msg("Shutdown signal received")

	// Shutdown context with configurable timeout
	shutdownTimeout := cfg.GetShutdownTimeoutDuration()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	log.Info().Dur("timeout", shutdownTimeout).Msg("Shutting down server...")

	// 1. Shutdown HTTP server
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Error().Err(err).Msg("HTTP server shutdown error")
	} else {
		log.Info().Msg("HTTP server shutdown complete")
	}

	// 2. Close database connections
	pool.Close()
	log.Info().Msg("Database pool closed")

	// 3. Shutdown tracer
	if tp != nil {
		if err := tp.Shutdown(shutdownCtx); err != nil {
			log.Error().Err(err).Msg("Tracer shutdown error")
		} else {
			log.Info().Msg("Tracer shutdown complete")
		}
	}

	log.Info().Msg("Graceful shutdown complete")
}
