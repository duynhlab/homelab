package middleware

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/duynhne/monitoring/pkg/config"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

var (
	tracer          trace.Tracer
	tracerProvider  *sdktrace.TracerProvider
	detectedService string
)

// InitTracing initializes OpenTelemetry tracing using centralized config package
// Configuration is loaded from environment variables via config.Load()
//
// Example:
//
//	cfg := config.Load()
//	tp, err := middleware.InitTracing(cfg)
//	defer tp.Shutdown(context.Background())
func InitTracing(cfg *config.Config) (*sdktrace.TracerProvider, error) {
	// Skip tracing initialization if disabled
	if !cfg.Tracing.Enabled {
		return nil, fmt.Errorf("tracing is disabled (TRACING_ENABLED=false)")
	}

	// Validate tracing configuration
	if cfg.Tracing.Endpoint == "" {
		return nil, fmt.Errorf("TEMPO_ENDPOINT is required when tracing is enabled")
	}
	if cfg.Tracing.SampleRate < 0 || cfg.Tracing.SampleRate > 1.0 {
		return nil, fmt.Errorf("OTEL_SAMPLE_RATE must be between 0.0 and 1.0, got: %.2f", cfg.Tracing.SampleRate)
	}

	// Create context with timeout for exporter initialization
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Create OTLP HTTP exporter with compression
	// Tempo endpoint: tempo.monitoring.svc.cluster.local:4318 (OTLP HTTP)
	exporter, err := otlptracehttp.New(
		ctx,
		otlptracehttp.WithEndpoint(cfg.Tracing.Endpoint),
		otlptracehttp.WithInsecure(), // Use TLS in production
		otlptracehttp.WithCompression(otlptracehttp.GzipCompression),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create OTLP exporter: %w", err)
	}

	// Auto-detect service information from Kubernetes environment
	// Falls back to cfg.Service.Name if Kubernetes metadata is unavailable
	res, err := CreateResource(context.Background())
	if err != nil {
		return nil, fmt.Errorf("failed to create resource: %w", err)
	}

	// Store detected service name for middleware usage
	detectedService = GetServiceName(res)
	if detectedService == "" || detectedService == "unknown-service" {
		detectedService = cfg.Service.Name
	}

	// Create tracer provider with batch export configuration
	// BatchTimeout: How often to flush spans (default: 5s)
	// ExportTimeout: Max time to wait for export (default: 30s)
	// SampleRate: Percentage of traces to sample (10% production, 100% dev)
	tracerProvider = sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter,
			sdktrace.WithBatchTimeout(5*time.Second),
			sdktrace.WithExportTimeout(30*time.Second),
			sdktrace.WithMaxExportBatchSize(cfg.Tracing.MaxExportBatchSize),
		),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.TraceIDRatioBased(cfg.Tracing.SampleRate)),
	)

	// Set global tracer provider
	otel.SetTracerProvider(tracerProvider)

	// Set global propagator for trace context propagation (W3C Trace Context)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	// Create tracer for this service using auto-detected name
	tracer = otel.Tracer(detectedService)

	return tracerProvider, nil
}

// shouldTrace determines if a request should be traced based on path
// Skips health checks, metrics endpoints, and static resources
func shouldTrace(path string) bool {
	skipPaths := []string{
		"/health", "/healthz", "/readyz", "/livez",
		"/metrics", "/favicon.ico",
	}
	for _, skip := range skipPaths {
		if strings.HasPrefix(path, skip) {
			return false
		}
	}
	return true
}

// TracingMiddleware returns a Gin middleware for OpenTelemetry tracing
// Service name is automatically detected from Kubernetes metadata
//
// Usage:
//
//	r := gin.Default()
//	r.Use(middleware.TracingMiddleware())
func TracingMiddleware() gin.HandlerFunc {
	serviceName := detectedService
	if serviceName == "" {
		serviceName = "unknown-service"
	}

	// Wrap otelgin middleware with request filtering
	otelMiddleware := otelgin.Middleware(
		serviceName,
		otelgin.WithTracerProvider(otel.GetTracerProvider()),
	)

	return func(c *gin.Context) {
		// Skip tracing for health checks and metrics endpoints
		if !shouldTrace(c.Request.URL.Path) {
			c.Next()
			return
		}

		// Apply OpenTelemetry middleware
		otelMiddleware(c)
	}
}

// GetTracer returns the tracer instance with auto-detected service name
func GetTracer() trace.Tracer {
	if tracer == nil {
		serviceName := detectedService
		if serviceName == "" {
			serviceName = "unknown-service"
		}
		tracer = otel.Tracer(serviceName)
	}
	return tracer
}

// StartSpan starts a new span with the given name
//
// Usage:
//
//	ctx, span := middleware.StartSpan(ctx, "database.query")
//	defer span.End()
func StartSpan(ctx context.Context, name string, opts ...trace.SpanStartOption) (context.Context, trace.Span) {
	return GetTracer().Start(ctx, name, opts...)
}

// Shutdown gracefully shuts down the tracer provider, flushing any pending spans
// Call this in main() before application exits to ensure all traces are exported
//
// Usage (Go 1.25 WaitGroup.Go):
//
//	var wg sync.WaitGroup
//	wg.Go(func() {
//	    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
//	    defer cancel()
//	    if err := middleware.Shutdown(ctx); err != nil {
//	        log.Error("Failed to shutdown tracing", zap.Error(err))
//	    }
//	})
func Shutdown(ctx context.Context) error {
	if tracerProvider == nil {
		return nil
	}

	// Force flush to ensure all pending spans are exported
	if err := tracerProvider.ForceFlush(ctx); err != nil {
		return fmt.Errorf("failed to flush traces: %w", err)
	}

	// Shutdown the tracer provider
	if err := tracerProvider.Shutdown(ctx); err != nil {
		return fmt.Errorf("failed to shutdown tracer provider: %w", err)
	}

	return nil
}

// Helper Functions

// AddSpanAttributes adds attributes to the current span if it's recording
//
// Usage:
//
//	middleware.AddSpanAttributes(ctx,
//	    attribute.String("user.id", userID),
//	    attribute.Int("order.items", len(items)),
//	)
func AddSpanAttributes(ctx context.Context, attrs ...attribute.KeyValue) {
	span := trace.SpanFromContext(ctx)
	if span.IsRecording() {
		span.SetAttributes(attrs...)
	}
}

// AddSpanEvent adds an event to the current span if it's recording
//
// Usage:
//
//	middleware.AddSpanEvent(ctx, "cache.hit",
//	    attribute.String("cache.key", key),
//	)
func AddSpanEvent(ctx context.Context, name string, attrs ...attribute.KeyValue) {
	span := trace.SpanFromContext(ctx)
	if span.IsRecording() {
		span.AddEvent(name, trace.WithAttributes(attrs...))
	}
}

// RecordError records an error in the current span if it's recording
//
// Usage:
//
//	if err != nil {
//	    middleware.RecordError(ctx, err)
//	    return err
//	}
func RecordError(ctx context.Context, err error) {
	span := trace.SpanFromContext(ctx)
	if span.IsRecording() {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
	}
}

// SetSpanStatus sets the status of the current span if it's recording
//
// Usage:
//
//	middleware.SetSpanStatus(ctx, codes.Ok, "request successful")
func SetSpanStatus(ctx context.Context, code codes.Code, description string) {
	span := trace.SpanFromContext(ctx)
	if span.IsRecording() {
		span.SetStatus(code, description)
	}
}
