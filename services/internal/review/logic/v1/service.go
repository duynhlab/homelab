package v1

import (
	"context"
	"fmt"

	"github.com/duynhne/monitoring/internal/review/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type ReviewService struct{}

func NewReviewService() *ReviewService {
	return &ReviewService{}
}

func (s *ReviewService) ListReviews(ctx context.Context) ([]domain.Review, error) {
	ctx, span := middleware.StartSpan(ctx, "review.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
	))
	defer span.End()

	reviews := []domain.Review{
		{ID: "1", ProductID: "1", UserID: "1", Rating: 5, Comment: "Great product!"},
		{ID: "2", ProductID: "2", UserID: "2", Rating: 4, Comment: "Good quality"},
	}
	return reviews, nil
}

func (s *ReviewService) CreateReview(ctx context.Context, req domain.CreateReviewRequest) (*domain.Review, error) {
	ctx, span := middleware.StartSpan(ctx, "review.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.id", req.ProductID),
	))
	defer span.End()

	// Mock logic: validate rating range
	if req.Rating < 1 || req.Rating > 5 {
		span.SetAttributes(attribute.Bool("review.created", false))
		return nil, fmt.Errorf("create review for product %q with rating %d: %w", req.ProductID, req.Rating, ErrInvalidRating)
	}

	review := &domain.Review{
		ID:        "new-review",
		ProductID: req.ProductID,
		UserID:    req.UserID,
		Rating:    req.Rating,
		Comment:   req.Comment,
	}
	span.SetAttributes(
		attribute.String("review.id", review.ID),
		attribute.Bool("review.created", true),
	)
	return review, nil
}

