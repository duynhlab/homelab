package middleware

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
	"strconv"
)

var (
	tracer          trace.Tracer
	tracerProvider  *sdktrace.TracerProvider
	detectedService string
)

// TracingConfig holds configuration for OpenTelemetry tracing
type TracingConfig struct {
	ServiceName      string
	ServiceNamespace string
	TempoEndpoint    string
	Insecure         bool
	SampleRate       float64
	ExportTimeout    time.Duration
	BatchTimeout     time.Duration
	SkipPaths        []string
}

// DefaultTracingConfig returns default tracing configuration
func DefaultTracingConfig() TracingConfig {
	// Default to 10% sampling for production, 100% for development
	sampleRate := 0.1
	env := os.Getenv("ENV")
	if env == "development" || env == "dev" {
		sampleRate = 1.0
	}

	// Allow override via environment variable
	if rate := os.Getenv("OTEL_SAMPLE_RATE"); rate != "" {
		if parsed, err := strconv.ParseFloat(rate, 64); err == nil {
			sampleRate = parsed
		}
	}

	return TracingConfig{
		TempoEndpoint: "tempo.monitoring.svc.cluster.local:4318",
		Insecure:      true,
		SampleRate:    sampleRate,
		ExportTimeout: 30 * time.Second,
		BatchTimeout:  5 * time.Second,
		SkipPaths: []string{
			"/health", "/healthz", "/readyz", "/livez",
			"/metrics", "/favicon.ico",
		},
	}
}

// Validate validates the tracing configuration
func (c TracingConfig) Validate() error {
	if c.SampleRate < 0 || c.SampleRate > 1 {
		return fmt.Errorf("invalid sample rate: %f (must be between 0 and 1)", c.SampleRate)
	}
	if c.TempoEndpoint == "" {
		return fmt.Errorf("tempo endpoint cannot be empty")
	}
	if c.ExportTimeout <= 0 {
		return fmt.Errorf("export timeout must be positive")
	}
	if c.BatchTimeout <= 0 {
		return fmt.Errorf("batch timeout must be positive")
	}
	return nil
}

// InitTracing initializes OpenTelemetry tracing with default configuration
func InitTracing() (*sdktrace.TracerProvider, error) {
	config := DefaultTracingConfig()
	return InitTracingWithConfig(config)
}

// InitTracingWithConfig initializes OpenTelemetry tracing with custom configuration
func InitTracingWithConfig(config TracingConfig) (*sdktrace.TracerProvider, error) {
	// Validate configuration
	if err := config.Validate(); err != nil {
		return nil, fmt.Errorf("invalid tracing configuration: %w", err)
	}

	// Get Tempo endpoint from config or environment
	tempoEndpoint := config.TempoEndpoint
	if endpoint := os.Getenv("TEMPO_ENDPOINT"); endpoint != "" {
		tempoEndpoint = endpoint
	}

	// Create OTLP HTTP exporter
	exporter, err := otlptracehttp.New(
		context.Background(),
		otlptracehttp.WithEndpoint(tempoEndpoint),
		otlptracehttp.WithInsecure(), // Use TLS in production
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create OTLP exporter: %w", err)
	}

	// Auto-detect service information from Kubernetes environment
	res, err := CreateResource(context.Background())
	if err != nil {
		return nil, fmt.Errorf("failed to create resource: %w", err)
	}

	// Store detected service name for middleware usage
	detectedService = GetServiceName(res)

	// Create tracer provider with batch export configuration
	tracerProvider = sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter,
			sdktrace.WithBatchTimeout(config.BatchTimeout),
			sdktrace.WithExportTimeout(config.ExportTimeout),
		),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.TraceIDRatioBased(config.SampleRate)),
	)

	// Set global tracer provider
	otel.SetTracerProvider(tracerProvider)

	// Set global propagator for trace context propagation
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	// Create tracer for this service using auto-detected name
	tracer = otel.Tracer(detectedService)

	return tracerProvider, nil
}

// shouldTrace determines if a request should be traced based on path
func shouldTrace(path string) bool {
	config := DefaultTracingConfig()
	for _, skip := range config.SkipPaths {
		if strings.HasPrefix(path, skip) {
			return false
		}
	}
	return true
}

// TracingMiddleware returns a Gin middleware for OpenTelemetry tracing
// Service name is automatically detected, no manual configuration needed
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
func StartSpan(ctx context.Context, name string, opts ...trace.SpanStartOption) (context.Context, trace.Span) {
	return GetTracer().Start(ctx, name, opts...)
}

// Shutdown gracefully shuts down the tracer provider, flushing any pending spans
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
func AddSpanAttributes(ctx context.Context, attrs ...attribute.KeyValue) {
	span := trace.SpanFromContext(ctx)
	if span.IsRecording() {
		span.SetAttributes(attrs...)
	}
}

// AddSpanEvent adds an event to the current span if it's recording
func AddSpanEvent(ctx context.Context, name string, attrs ...attribute.KeyValue) {
	span := trace.SpanFromContext(ctx)
	if span.IsRecording() {
		span.AddEvent(name, trace.WithAttributes(attrs...))
	}
}

// RecordError records an error in the current span if it's recording
func RecordError(ctx context.Context, err error) {
	span := trace.SpanFromContext(ctx)
	if span.IsRecording() {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
	}
}

// SetSpanStatus sets the status of the current span if it's recording
func SetSpanStatus(ctx context.Context, code codes.Code, description string) {
	span := trace.SpanFromContext(ctx)
	if span.IsRecording() {
		span.SetStatus(code, description)
	}
}
