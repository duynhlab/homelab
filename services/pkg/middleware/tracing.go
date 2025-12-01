package middleware

import (
	"context"
	"os"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
	"go.opentelemetry.io/otel/trace"
)

var tracer trace.Tracer

// InitTracing initializes OpenTelemetry tracing
func InitTracing() (*sdktrace.TracerProvider, error) {
	// Get service name from environment
	serviceName := getAppName()
	if serviceName == "" {
		serviceName = "unknown-service"
	}

	// Get Tempo endpoint from environment (default to localhost for development)
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

	// Create resource with service information
	res, err := resource.New(
		context.Background(),
		resource.WithAttributes(
			semconv.ServiceNameKey.String(serviceName),
			semconv.ServiceNamespaceKey.String(getNamespace()),
		),
	)
	if err != nil {
		return nil, err
	}

	// Create tracer provider
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()), // Sample all traces for now
	)

	// Set global tracer provider
	otel.SetTracerProvider(tp)

	// Set global propagator for trace context propagation
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	// Create tracer for this service
	tracer = otel.Tracer(serviceName)

	return tp, nil
}

// TracingMiddleware returns a Gin middleware for OpenTelemetry tracing
func TracingMiddleware() gin.HandlerFunc {
	return otelgin.Middleware(
		getAppName(),
		otelgin.WithTracerProvider(otel.GetTracerProvider()),
	)
}

// GetTracer returns the tracer instance
func GetTracer() trace.Tracer {
	if tracer == nil {
		tracer = otel.Tracer(getAppName())
	}
	return tracer
}

// StartSpan starts a new span with the given name
func StartSpan(ctx context.Context, name string, opts ...trace.SpanStartOption) (context.Context, trace.Span) {
	return GetTracer().Start(ctx, name, opts...)
}

