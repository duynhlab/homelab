package v2

import (
	"errors"
	"net/http"

	"github.com/duynhne/monitoring/internal/review/core/domain"
	logicv2 "github.com/duynhne/monitoring/internal/review/logic/v2"
	"github.com/duynhne/monitoring/pkg/middleware"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

var reviewService = logicv2.NewReviewService()

func GetReview(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)
	reviewId := c.Param("reviewId")
	span.SetAttributes(attribute.String("review.id", reviewId))

	review, err := reviewService.GetReview(ctx, reviewId)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to get review", zap.Error(err), zap.String("review_id", reviewId))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Review retrieved", zap.String("review_id", reviewId))
	c.JSON(http.StatusOK, review)
}

func CreateReview(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("api.version", "v2"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	var req domain.CreateReviewRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		span.SetAttributes(attribute.Bool("request.valid", false))
		span.RecordError(err)
		zapLogger.Error("Invalid request", zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	span.SetAttributes(attribute.Bool("request.valid", true))
	review, err := reviewService.CreateReview(ctx, req)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to create review", zap.Error(err))

		switch {
		case errors.Is(err, logicv2.ErrInvalidRating):
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid rating (must be 1-5)"})
		case errors.Is(err, logicv2.ErrDuplicateReview):
			c.JSON(http.StatusConflict, gin.H{"error": "Review already exists"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Review created", zap.String("review_id", review.ID))
	c.JSON(http.StatusCreated, review)
}
