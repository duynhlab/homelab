package zerolog

import (
	"context"
	"os"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"go.opentelemetry.io/otel/trace"
)

// Setup initializes the global zerolog configuration.
func Setup() {
	// Standardize timestamp
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix

	// Set global log level to INFO (1) by default
	zerolog.SetGlobalLevel(zerolog.InfoLevel)

	// Configure global logger to write to stdout
	log.Logger = zerolog.New(os.Stdout).With().Timestamp().Logger()
}

// WithContext returns a context with the logger attached.
func WithContext(ctx context.Context) context.Context {
	// We can update the logger in the context with trace info here if needed,
	// but usually we want to attach the *instance* of the logger.
	// For zerolog, typical pattern is creating a sub-logger with context fields.

	l := log.Logger
	if span := trace.SpanFromContext(ctx); span.SpanContext().IsValid() {
		l = l.With().
			Str("trace_id", span.SpanContext().TraceID().String()).
			Str("span_id", span.SpanContext().SpanID().String()).
			Logger()
	}
	return l.WithContext(ctx)
}

// FromContext returns the logger from context.
func FromContext(ctx context.Context) *zerolog.Logger {
	return zerolog.Ctx(ctx)
}
