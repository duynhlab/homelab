package v1

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/duynhne/monitoring/internal/review/core/domain"
	logicv1 "github.com/duynhne/monitoring/internal/review/logic/v1"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

var reviewService = logicv1.NewReviewService()

func ListReviews(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("method", c.Request.Method),
		attribute.String("path", c.Request.URL.Path),
	))
	defer span.End()

	zapLogger := middleware.GetLoggerFromGinContext(c)

	reviews, err := reviewService.ListReviews(ctx)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to list reviews", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Reviews listed", zap.Int("count", len(reviews)))
	c.JSON(http.StatusOK, reviews)
}

func CreateReview(c *gin.Context) {
	ctx, span := middleware.StartSpan(c.Request.Context(), "http.request", trace.WithAttributes(
		attribute.String("layer", "web"),
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
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Review created", zap.String("review_id", review.ID))
	c.JSON(http.StatusCreated, review)
}

