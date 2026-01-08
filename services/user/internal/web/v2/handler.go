package v2

import (
	"errors"
	"net/http"

	"github.com/duynhne/monitoring/services/user/internal/core/domain"
	logicv2 "github.com/duynhne/monitoring/services/user/internal/logic/v2"
	"github.com/duynhne/monitoring/services/user/middleware"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

var userService = logicv2.NewUserService()

// GetUser handles HTTP request to get a user by ID (v2)
func GetUser(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
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

	id := c.Param("id")
	span.SetAttributes(attribute.String("user.id", id))

	user, err := userService.GetUser(ctx, id)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to get user", zap.Error(err))

		switch {
		case errors.Is(err, logicv2.ErrUserNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("User retrieved", zap.String("user_id", id))
	c.JSON(http.StatusOK, user)
}

// GetProfile handles HTTP request to get current user profile (v2)
func GetProfile(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
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

	user, err := userService.GetProfile(ctx)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to get profile", zap.Error(err))

		switch {
		case errors.Is(err, logicv2.ErrUnauthorized):
			c.JSON(http.StatusForbidden, gin.H{"error": "Unauthorized access"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Profile retrieved")
	c.JSON(http.StatusOK, user)
}

// CreateUser handles HTTP request to create a new user (v2)
func CreateUser(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
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

	var req domain.CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		span.SetAttributes(attribute.Bool("request.valid", false))
		span.RecordError(err)
		zapLogger.Error("Invalid request", zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	span.SetAttributes(attribute.Bool("request.valid", true))

	user, err := userService.CreateUser(ctx, req)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to create user", zap.Error(err))

		switch {
		case errors.Is(err, logicv2.ErrUserExists):
			c.JSON(http.StatusConflict, gin.H{"error": "User already exists"})
		case errors.Is(err, logicv2.ErrInvalidEmail):
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid email address"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("User created", zap.String("user_id", user.ID))
	c.JSON(http.StatusCreated, user)
}
