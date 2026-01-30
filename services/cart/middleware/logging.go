package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"time"

	"github.com/duynhne/monitoring/services/pkg/logger/clog"
	"github.com/gin-gonic/gin"
)

const TraceIDHeader = "X-Trace-ID"
const TraceParentHeader = "traceparent"

// GetTraceID extracts trace-id from request headers or generates a new one
func GetTraceID(c *gin.Context) string {
	// Try W3C Trace Context first (traceparent header)
	if traceParent := c.GetHeader(TraceParentHeader); traceParent != "" {
		// traceparent format: version-trace_id-parent_id-flags
		// Extract trace_id (second part)
		parts := splitTraceParent(traceParent)
		if len(parts) >= 2 && parts[1] != "" {
			return parts[1]
		}
	}

	// Fallback to X-Trace-ID header
	if traceID := c.GetHeader(TraceIDHeader); traceID != "" {
		return traceID
	}

	// Generate new trace-id if not present
	return generateTraceID()
}

// splitTraceParent splits traceparent header value
func splitTraceParent(traceParent string) []string {
	// Simple split by hyphen, traceparent format: 00-<trace_id>-<parent_id>-<flags>
	parts := make([]string, 0, 4)
	start := 0
	for i := 0; i < len(traceParent); i++ {
		if traceParent[i] == '-' {
			if start < i {
				parts = append(parts, traceParent[start:i])
			}
			start = i + 1
		}
	}
	if start < len(traceParent) {
		parts = append(parts, traceParent[start:])
	}
	return parts
}

// generateTraceID generates a trace-id using random bytes
func generateTraceID() string {
	// Generate 16 random bytes (32 hex characters)
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// LoggingMiddleware creates a Gin middleware for structured logging with trace-id
func LoggingMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		method := c.Request.Method

		// Get or generate trace-id
		traceID := GetTraceID(c)

		// Store trace-id in context for handlers to use
		c.Set("trace_id", traceID)

		// Setup logger with trace_id
		ctx := c.Request.Context()
		logger := slog.Default().With("trace_id", traceID)

		// Inject logger into context
		ctx = clog.WithLogger(ctx, logger)
		c.Request = c.Request.WithContext(ctx)

		// Create a helper to get logger from gin context explicitly if needed (legacy compatibility)
		c.Set("logger", logger)

		// Add trace-id to response header
		c.Header(TraceIDHeader, traceID)

		// Process request
		c.Next()

		// Calculate duration
		duration := time.Since(start)
		statusCode := c.Writer.Status()

		// Log request/response
		clog.InfoContext(ctx, "HTTP request",
			"method", method,
			"path", path,
			"status", statusCode,
			"duration", duration,
			"client_ip", c.ClientIP(),
			"user_agent", c.Request.UserAgent(),
		)

		// Log errors (4xx, 5xx)
		if statusCode >= 400 {
			clog.ErrorContext(ctx, "HTTP error",
				"method", method,
				"path", path,
				"status", statusCode,
				"duration", duration,
			)
		}
	}
}

// GetLoggerFromContext retrieves logger from Gin context (legacy adapter)
// New code should use clog.FromContext(ctx) directly
func GetLoggerFromGinContext(c *gin.Context) *slog.Logger {
	return clog.FromContext(c.Request.Context())
}
