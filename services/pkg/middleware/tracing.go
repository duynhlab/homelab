package middleware

import (
	"context"
	"os"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
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

// InitTracing initializes OpenTelemetry tracing with automatic resource detection
func InitTracing() (*sdktrace.TracerProvider, error) {
	// Get Tempo endpoint from environment
	tempoEndpoint := os.Getenv("TEMPO_ENDPOINT")
	if tempoEndpoint == "" {
		tempoEndpoint = "http://tempo.monitoring.svc.cluster.local:4318"
	}

	// Create OTLP HTTP exporter
	exporter, err := otlptracehttp.New(
		context.Background(),
		otlptracehttp.WithEndpoint(tempoEndpoint),
		otlptracehttp.WithInsecure(), // Use TLS in production
	)
	if err != nil {
		return nil, err
	}

	// Auto-detect service information from Kubernetes environment
	// This eliminates the need for manual APP_NAME/NAMESPACE env vars
	res, err := createResource()
	if err != nil {
		return nil, err
	}
	
	// Store detected service name for middleware usage
	detectedService = GetServiceName(res)

	// Create tracer provider
	tracerProvider = sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()), // Sample all traces for now
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

// TracingMiddleware returns a Gin middleware for OpenTelemetry tracing
// Service name is automatically detected, no manual configuration needed
func TracingMiddleware() gin.HandlerFunc {
	serviceName := detectedService
	if serviceName == "" {
		serviceName = "unknown-service"
	}
	return otelgin.Middleware(
		serviceName,
		otelgin.WithTracerProvider(otel.GetTracerProvider()),
	)
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

