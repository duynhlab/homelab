// Package config provides centralized configuration management for all microservices
// with validation, type safety, and clear documentation for SRE/DevOps teams.
//
// Configuration Sources (12-factor app principles):
//  1. Default values (hardcoded)
//  2. .env file (local development via godotenv)
//  3. Environment variables (Kubernetes runtime)
//  4. Helm values → deployment.yaml → env/extraEnv → container environment
//
// Usage:
//
//	import "github.com/duynhne/monitoring/pkg/config"
//
//	func main() {
//	    cfg := config.Load()
//	    if err := cfg.Validate(); err != nil {
//	        log.Fatal(err)
//	    }
//	    // Use cfg.Service.Port, cfg.Tracing.Endpoint, etc.
//	}
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

// Config holds all configuration for a microservice
type Config struct {
	Service  ServiceConfig  // Service-specific settings (port, name, version)
	Tracing  TracingConfig  // OpenTelemetry/Tempo configuration
	Profiling ProfilingConfig // Pyroscope continuous profiling
	Logging  LoggingConfig  // Structured logging (Zap)
	Metrics  MetricsConfig  // Prometheus metrics
}

// ServiceConfig defines basic service configuration
type ServiceConfig struct {
	Name    string // Service name (e.g., "auth", "user") - from SERVICE_NAME env
	Port    string // HTTP server port (default: "8080") - from PORT env
	Version string // Service version (optional) - from VERSION env
	Env     string // Environment (dev/staging/production) - from ENV env
}

// TracingConfig defines OpenTelemetry tracing configuration
// Traces are sent to OpenTelemetry Collector for distributed tracing analysis
type TracingConfig struct {
	Enabled       bool    // Enable tracing (default: true) - from TRACING_ENABLED env
	Endpoint      string  // OTel Collector endpoint - from OTEL_COLLECTOR_ENDPOINT env
	SampleRate    float64 // Trace sampling rate (0.0-1.0) - from OTEL_SAMPLE_RATE env
	ServiceName   string  // Service name for traces (defaults to ServiceConfig.Name)
	MaxExportBatchSize int // Max spans per batch (default: 512)
}

// ProfilingConfig defines Pyroscope continuous profiling configuration
type ProfilingConfig struct {
	Enabled     bool   // Enable profiling (default: true) - from PROFILING_ENABLED env
	Endpoint    string // Pyroscope endpoint - from PYROSCOPE_ENDPOINT env
	ServiceName string // Service name for profiling (defaults to ServiceConfig.Name)
}

// LoggingConfig defines structured logging configuration
type LoggingConfig struct {
	Level  string // Log level: debug, info, warn, error (default: "info") - from LOG_LEVEL env
	Format string // Log format: json, console (default: "json") - from LOG_FORMAT env
}

// MetricsConfig defines Prometheus metrics configuration
type MetricsConfig struct {
	Enabled bool   // Enable metrics (default: true) - from METRICS_ENABLED env
	Path    string // Metrics endpoint path (default: "/metrics") - from METRICS_PATH env
}

// Load reads configuration from environment variables with defaults
// It automatically loads .env file if present (for local development)
//
// Priority: .env file < environment variables
// This means ENV vars override .env file values (production takes precedence)
func Load() *Config {
	// Load .env file if exists (for local development)
	// godotenv.Load() fails silently if .env doesn't exist - perfect for production
	_ = godotenv.Load()

	return &Config{
		Service: ServiceConfig{
			Name:    getEnv("SERVICE_NAME", "unknown"),
			Port:    getEnv("PORT", "8080"),
			Version: getEnv("VERSION", "dev"),
			Env:     getEnv("ENV", "development"),
		},
		Tracing: TracingConfig{
			Enabled:            getEnvBool("TRACING_ENABLED", true),
			Endpoint:           getEnv("OTEL_COLLECTOR_ENDPOINT", "otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318"),
			SampleRate:         getEnvFloat("OTEL_SAMPLE_RATE", 0.1), // 10% default (production)
			ServiceName:        getEnv("SERVICE_NAME", "unknown"),
			MaxExportBatchSize: getEnvInt("OTEL_BATCH_SIZE", 512),
		},
		Profiling: ProfilingConfig{
			Enabled:     getEnvBool("PROFILING_ENABLED", true),
			Endpoint:    getEnv("PYROSCOPE_ENDPOINT", "http://pyroscope.monitoring.svc.cluster.local:4040"),
			ServiceName: getEnv("SERVICE_NAME", "unknown"),
		},
		Logging: LoggingConfig{
			Level:  getEnv("LOG_LEVEL", "info"),
			Format: getEnv("LOG_FORMAT", "json"),
		},
		Metrics: MetricsConfig{
			Enabled: getEnvBool("METRICS_ENABLED", true),
			Path:    getEnv("METRICS_PATH", "/metrics"),
		},
	}
}

// Validate performs comprehensive validation of all configuration fields
// Returns detailed error messages for SRE/DevOps troubleshooting
func (c *Config) Validate() error {
	var errors []string

	// Service validation
	if c.Service.Name == "" || c.Service.Name == "unknown" {
		errors = append(errors, "SERVICE_NAME is required (e.g., 'auth', 'user', 'product')")
	}
	if c.Service.Port == "" {
		errors = append(errors, "PORT is required (e.g., '8080')")
	}
	// Validate port is a valid number
	if _, err := strconv.Atoi(c.Service.Port); err != nil {
		errors = append(errors, fmt.Sprintf("PORT must be a valid number, got: %s", c.Service.Port))
	}
	// Validate environment
	validEnvs := []string{"development", "dev", "staging", "stage", "production", "prod"}
	if !contains(validEnvs, c.Service.Env) {
		errors = append(errors, fmt.Sprintf("ENV must be one of %v, got: %s", validEnvs, c.Service.Env))
	}

	// Tracing validation
	if c.Tracing.Enabled {
		if c.Tracing.Endpoint == "" {
			errors = append(errors, "OTEL_COLLECTOR_ENDPOINT is required when tracing is enabled")
		}
		if c.Tracing.SampleRate < 0 || c.Tracing.SampleRate > 1.0 {
			errors = append(errors, fmt.Sprintf("OTEL_SAMPLE_RATE must be between 0.0 and 1.0, got: %.2f", c.Tracing.SampleRate))
		}
		if c.Tracing.ServiceName == "" || c.Tracing.ServiceName == "unknown" {
			errors = append(errors, "SERVICE_NAME is required for tracing (used in Tempo queries)")
		}
	}

	// Profiling validation
	if c.Profiling.Enabled {
		if c.Profiling.Endpoint == "" {
			errors = append(errors, "PYROSCOPE_ENDPOINT is required when profiling is enabled")
		}
		if c.Profiling.ServiceName == "" || c.Profiling.ServiceName == "unknown" {
			errors = append(errors, "SERVICE_NAME is required for profiling (used in Pyroscope UI)")
		}
	}

	// Logging validation
	validLogLevels := []string{"debug", "info", "warn", "error"}
	if !contains(validLogLevels, strings.ToLower(c.Logging.Level)) {
		errors = append(errors, fmt.Sprintf("LOG_LEVEL must be one of %v, got: %s", validLogLevels, c.Logging.Level))
	}
	validLogFormats := []string{"json", "console"}
	if !contains(validLogFormats, strings.ToLower(c.Logging.Format)) {
		errors = append(errors, fmt.Sprintf("LOG_FORMAT must be one of %v, got: %s", validLogFormats, c.Logging.Format))
	}

	if len(errors) > 0 {
		return fmt.Errorf("configuration validation failed:\n  - %s", strings.Join(errors, "\n  - "))
	}

	return nil
}

// IsDevelopment returns true if running in development environment
func (c *Config) IsDevelopment() bool {
	env := strings.ToLower(c.Service.Env)
	return env == "development" || env == "dev"
}

// IsProduction returns true if running in production environment
func (c *Config) IsProduction() bool {
	env := strings.ToLower(c.Service.Env)
	return env == "production" || env == "prod"
}

// Helper functions for environment variable parsing

// getEnv reads an environment variable with a default fallback
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvBool reads a boolean environment variable with a default fallback
// Accepts: "true", "1", "yes" for true | "false", "0", "no" for false
func getEnvBool(key string, defaultValue bool) bool {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	value = strings.ToLower(value)
	return value == "true" || value == "1" || value == "yes"
}

// getEnvInt reads an integer environment variable with a default fallback
// Returns default if parsing fails
func getEnvInt(key string, defaultValue int) int {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	intValue, err := strconv.Atoi(value)
	if err != nil {
		return defaultValue
	}
	return intValue
}

// getEnvFloat reads a float64 environment variable with a default fallback
// Returns default if parsing fails
func getEnvFloat(key string, defaultValue float64) float64 {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	floatValue, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return defaultValue
	}
	return floatValue
}

// contains checks if a string slice contains a specific value
func contains(slice []string, item string) bool {
	for _, s := range slice {
		if strings.EqualFold(s, item) {
			return true
		}
	}
	return false
}

