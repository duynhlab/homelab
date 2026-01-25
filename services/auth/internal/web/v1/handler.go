package v1

import (
	"errors"
	"net/http"

	"github.com/duynhne/monitoring/services/auth/internal/core/domain"
	logicv1 "github.com/duynhne/monitoring/services/auth/internal/logic/v1"
	"github.com/duynhne/monitoring/services/auth/middleware"
	"github.com/gin-gonic/gin"
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
		// Log the full error with context (error chain includes username)
		zapLogger.Error("Login failed", zap.Error(err))

		// Check error type using errors.Is() and map to appropriate HTTP response
		switch {
		case errors.Is(err, logicv1.ErrInvalidCredentials):
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		case errors.Is(err, logicv1.ErrUserNotFound):
			// Don't reveal that user doesn't exist (security best practice)
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		case errors.Is(err, logicv1.ErrPasswordExpired):
			c.JSON(http.StatusForbidden, gin.H{"error": "Password expired"})
		case errors.Is(err, logicv1.ErrAccountLocked):
			c.JSON(http.StatusForbidden, gin.H{"error": "Account locked"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
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

		// Check error type and map to appropriate HTTP response
		switch {
		case errors.Is(err, logicv1.ErrUserExists):
			c.JSON(http.StatusConflict, gin.H{"error": "Username or email already exists"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Registration successful", zap.String("user_id", response.User.ID))
	c.JSON(http.StatusCreated, response)
}

// GetMe handles HTTP request to get current user from session token
// GET /api/v1/auth/me
// Authorization: Bearer <token>
func GetMe(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

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

	// Extract token from Authorization header
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" {
		span.SetAttributes(attribute.Bool("auth.present", false))
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header required"})
		return
	}

	// Expect "Bearer <token>"
	const bearerPrefix = "Bearer "
	if len(authHeader) <= len(bearerPrefix) || authHeader[:len(bearerPrefix)] != bearerPrefix {
		span.SetAttributes(attribute.Bool("auth.valid_format", false))
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid authorization format"})
		return
	}
	token := authHeader[len(bearerPrefix):]

	span.SetAttributes(attribute.Bool("auth.present", true))

	// Lookup user by token
	user, err := authService.GetUserByToken(ctx, token)
	if err != nil {
		span.RecordError(err)
		zapLogger.Warn("Token lookup failed", zap.Error(err))

		switch {
		case errors.Is(err, logicv1.ErrSessionNotFound):
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired token"})
		case errors.Is(err, logicv1.ErrSessionExpired):
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Session expired"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Token validated", zap.String("user_id", user.ID))
	c.JSON(http.StatusOK, user)
}
