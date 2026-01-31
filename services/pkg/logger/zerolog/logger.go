package zerolog

import (
	"context"
	"os"
	"strings"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"go.opentelemetry.io/otel/trace"
)

// Setup initializes the global zerolog configuration.
// level is parsed from LOG_LEVEL env (debug, info, warn, error). Defaults to info if invalid.
func Setup(level string) {
	// Standardize timestamp
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix

	// Set global log level from config
	zerolog.SetGlobalLevel(parseZerologLevel(level))

	// Configure global logger to write to stdout
	log.Logger = zerolog.New(os.Stdout).With().Timestamp().Logger()
}

// parseZerologLevel maps config level string to zerolog.Level. Defaults to info for unknown values.
func parseZerologLevel(level string) zerolog.Level {
	switch strings.ToLower(strings.TrimSpace(level)) {
	case "debug":
		return zerolog.DebugLevel
	case "info":
		return zerolog.InfoLevel
	case "warn":
		return zerolog.WarnLevel
	case "error":
		return zerolog.ErrorLevel
	default:
		return zerolog.InfoLevel
	}
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
