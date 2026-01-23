package v1

import (
	"errors"
	"net/http"

	"github.com/duynhne/monitoring/services/review/internal/core/domain"
	logicv1 "github.com/duynhne/monitoring/services/review/internal/logic/v1"
	"github.com/duynhne/monitoring/services/review/middleware"
	"github.com/gin-gonic/gin"
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

	// Parse product_id from query string (required)
	productID := c.Query("product_id")
	if productID == "" {
		span.SetAttributes(attribute.Bool("request.valid", false))
		zapLogger.Error("Missing product_id query parameter")
		c.JSON(http.StatusBadRequest, gin.H{"error": "product_id query parameter is required"})
		return
	}
	span.SetAttributes(attribute.String("product.id", productID))

	reviews, err := reviewService.ListReviews(ctx, productID)
	if err != nil {
		span.RecordError(err)
		zapLogger.Error("Failed to list reviews", zap.Error(err), zap.String("product_id", productID))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		return
	}

	zapLogger.Info("Reviews listed", zap.Int("count", len(reviews)), zap.String("product_id", productID))
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

		switch {
		case errors.Is(err, logicv1.ErrInvalidRating):
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid rating (must be 1-5)"})
		case errors.Is(err, logicv1.ErrDuplicateReview):
			c.JSON(http.StatusConflict, gin.H{"error": "Review already exists"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
		}
		return
	}

	zapLogger.Info("Review created", zap.String("review_id", review.ID))
	c.JSON(http.StatusCreated, review)
}
