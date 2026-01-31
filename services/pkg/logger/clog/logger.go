package clog

import (
	"context"
	"log/slog"
	"os"
	"strings"

	"github.com/chainguard-dev/clog"
	"go.opentelemetry.io/otel/trace"
)

// Setup initializes the global logger with a JSON handler and tracing support.
// level is parsed from LOG_LEVEL env (debug, info, warn, error). Defaults to info if invalid.
func Setup(level string) {
	slogLevel := parseSlogLevel(level)
	handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slogLevel,
	})

	// Create a logger with the tracing handler
	logger := slog.New(&TracingHandler{handler: handler})
	slog.SetDefault(logger)
}

// TracingHandler is a middleware that injects trace_id and span_id from context.
type TracingHandler struct {
	handler slog.Handler
}

func (h *TracingHandler) Enabled(ctx context.Context, level slog.Level) bool {
	return h.handler.Enabled(ctx, level)
}

func (h *TracingHandler) Handle(ctx context.Context, r slog.Record) error {
	if span := trace.SpanFromContext(ctx); span.SpanContext().IsValid() {
		// Inject standard trace attributes
		r.AddAttrs(
			slog.String("trace_id", span.SpanContext().TraceID().String()),
			slog.String("span_id", span.SpanContext().SpanID().String()),
		)
	}
	return h.handler.Handle(ctx, r)
}

func (h *TracingHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return &TracingHandler{handler: h.handler.WithAttrs(attrs)}
}

func (h *TracingHandler) WithGroup(name string) slog.Handler {
	return &TracingHandler{handler: h.handler.WithGroup(name)}
}

// parseSlogLevel maps config level string to slog.Level. Defaults to info for unknown values.
func parseSlogLevel(level string) slog.Level {
	switch strings.ToLower(strings.TrimSpace(level)) {
	case "debug":
		return slog.LevelDebug
	case "info":
		return slog.LevelInfo
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

// WithLogger is a helper to inject logger into context using clog
func WithLogger(ctx context.Context, l *slog.Logger) context.Context {
	// clog.New takes a slog.Handler and returns *clog.Logger
	return clog.WithLogger(ctx, clog.New(l.Handler()))
}

// FromContext is a helper to extract logger from context using clog
func FromContext(ctx context.Context) *slog.Logger {
	cl := clog.FromContext(ctx)
	// clog.Logger has a Handler() method (it embeds/wraps slog.Logger capabilities)
	return slog.New(cl.Handler())
}

// Aliases for convenience so calling code doesn't need to import clog directly
func InfoContext(ctx context.Context, msg string, args ...any) {
	FromContext(ctx).InfoContext(ctx, msg, args...)
}

func ErrorContext(ctx context.Context, msg string, args ...any) {
	FromContext(ctx).ErrorContext(ctx, msg, args...)
}

func WarnContext(ctx context.Context, msg string, args ...any) {
	FromContext(ctx).WarnContext(ctx, msg, args...)
}

func DebugContext(ctx context.Context, msg string, args ...any) {
	FromContext(ctx).DebugContext(ctx, msg, args...)
}
