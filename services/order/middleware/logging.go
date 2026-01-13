package middleware

import (
	"crypto/rand"
	"encoding/hex"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
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
func LoggingMiddleware(logger *zap.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		method := c.Request.Method

		// Get or generate trace-id
		traceID := GetTraceID(c)

		// Store trace-id in context for handlers to use
		c.Set("trace_id", traceID)

		// Store logger in context for handlers to use
		loggerWithTrace := logger.With(zap.String("trace_id", traceID))
		c.Set("logger", loggerWithTrace)

		// Add trace-id to response header
		c.Header(TraceIDHeader, traceID)

		// Process request
		c.Next()

		// Calculate duration
		duration := time.Since(start)
		statusCode := c.Writer.Status()

		// Log request/response
		logger.Info("HTTP request",
			zap.String("trace_id", traceID),
			zap.String("method", method),
			zap.String("path", path),
			zap.Int("status", statusCode),
			zap.Duration("duration", duration),
			zap.String("client_ip", c.ClientIP()),
			zap.String("user_agent", c.Request.UserAgent()),
		)

		// Log errors (4xx, 5xx) with error level
		if statusCode >= 400 {
			logger.Error("HTTP error",
				zap.String("trace_id", traceID),
				zap.String("method", method),
				zap.String("path", path),
				zap.Int("status", statusCode),
				zap.Duration("duration", duration),
			)
		}
	}
}

// GetLoggerFromContext retrieves logger with trace-id from Gin context
func GetLoggerFromContext(c *gin.Context, baseLogger *zap.Logger) *zap.Logger {
	traceID, exists := c.Get("trace_id")
	if !exists {
		return baseLogger
	}
	return baseLogger.With(zap.String("trace_id", traceID.(string)))
}

// GetLoggerFromGinContext retrieves logger from Gin context (set by LoggingMiddleware)
func GetLoggerFromGinContext(c *gin.Context) *zap.Logger {
	loggerVal, exists := c.Get("logger")
	if exists {
		if l, ok := loggerVal.(*zap.Logger); ok {
			return l
		}
	}
	// Fallback: create a basic logger
	logger, _ := NewLogger()
	return logger
}

// NewLogger creates a new zap logger with JSON encoder for production
func NewLogger() (*zap.Logger, error) {
	config := zap.NewProductionConfig()
	config.EncoderConfig.TimeKey = "timestamp"
	config.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder
	config.EncoderConfig.MessageKey = "message"
	config.EncoderConfig.LevelKey = "level"
	config.EncoderConfig.CallerKey = "caller"

	return config.Build()
}

// NewDevelopmentLogger creates a new zap logger for development (console encoder)
func NewDevelopmentLogger() (*zap.Logger, error) {
	config := zap.NewDevelopmentConfig()
	config.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder
	return config.Build()
}
