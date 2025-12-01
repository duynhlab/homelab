package v1

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/duynhne/monitoring/internal/auth/core/domain"
	logicv1 "github.com/duynhne/monitoring/internal/auth/logic/v1"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

var authService = logicv1.NewAuthService()

// Login handles HTTP request for user login
func Login(c *gin.Context) {
	// Create span for web layer
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	// Get logger from context (set by logging middleware)
	loggerVal, exists := c.Get("logger")
	var zapLogger *zap.Logger
	if exists {
		if l, ok := loggerVal.(*zap.Logger); ok {
			zapLogger = l
		}
	}
	if zapLogger == nil {
		// Fallback: create a basic logger
		zapLogger, _ = middleware.NewLogger()
	}

	var req domain.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		span.SetAttributes(attribute.Bool("request.valid", false))
		span.RecordError(err)
		zapLogger.Error("Invalid request", zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	span.SetAttributes(attribute.Bool("request.valid", true))

	// Call business logic layer
	response, err := authService.Login(ctx, req)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Login failed", zap.Error(err), zap.String("username", req.Username))
		
		if authErr, ok := err.(*logicv1.AuthError); ok && authErr.Code == "INVALID_CREDENTIALS" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": authErr.Message})
			return
		}
		
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Login successful", zap.String("user_id", response.User.ID))
	c.JSON(http.StatusOK, response)
}

// Register handles HTTP request for user registration
func Register(c *gin.Context) {
	// Create span for web layer
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	// Get logger from context (set by logging middleware)
	loggerVal, exists := c.Get("logger")
	var zapLogger *zap.Logger
	if exists {
		if l, ok := loggerVal.(*zap.Logger); ok {
			zapLogger = l
		}
	}
	if zapLogger == nil {
		zapLogger, _ = middleware.NewLogger()
	}

	var req domain.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		span.SetAttributes(attribute.Bool("request.valid", false))
		span.RecordError(err)
		zapLogger.Error("Invalid request", zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	span.SetAttributes(attribute.Bool("request.valid", true))

	// Call business logic layer
	response, err := authService.Register(ctx, req)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Registration failed", zap.Error(err), zap.String("username", req.Username))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Registration successful", zap.String("user_id", response.User.ID))
	c.JSON(http.StatusCreated, response)
}
