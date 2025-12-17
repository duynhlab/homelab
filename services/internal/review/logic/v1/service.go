package v1

import (
	"context"
	"database/sql"
	"fmt"
	"strconv"

	database "github.com/duynhne/monitoring/internal/review/core"
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

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Query reviews
	query := `SELECT id, product_id, user_id, rating, title, comment FROM reviews ORDER BY created_at DESC`
	rows, err := db.QueryContext(ctx, query)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("query reviews: %w", err)
	}
	defer rows.Close()

	var reviews []domain.Review
	for rows.Next() {
		var reviewID, productID, userID int
		var rating int
		var title, comment sql.NullString

		err := rows.Scan(&reviewID, &productID, &userID, &rating, &title, &comment)
		if err != nil {
			span.RecordError(err)
			continue
		}

		review := domain.Review{
			ID:        strconv.Itoa(reviewID),
			ProductID: strconv.Itoa(productID),
			UserID:    strconv.Itoa(userID),
			Rating:    rating,
		}
		if comment.Valid {
			review.Comment = comment.String
		}

		reviews = append(reviews, review)
	}

	if err = rows.Err(); err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("scan reviews: %w", err)
	}

	span.SetAttributes(attribute.Int("reviews.count", len(reviews)))
	return reviews, nil
}

func (s *ReviewService) CreateReview(ctx context.Context, req domain.CreateReviewRequest) (*domain.Review, error) {
	ctx, span := middleware.StartSpan(ctx, "review.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.id", req.ProductID),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Validate rating range
	if req.Rating < 1 || req.Rating > 5 {
		span.SetAttributes(attribute.Bool("review.created", false))
		return nil, fmt.Errorf("create review for product %q with rating %d: %w", req.ProductID, req.Rating, ErrInvalidRating)
	}

	// Convert IDs to int
	productID, err := strconv.Atoi(req.ProductID)
	if err != nil {
		return nil, fmt.Errorf("invalid product id %q: %w", req.ProductID, ErrInvalidRating)
	}
	userID, err := strconv.Atoi(req.UserID)
	if err != nil {
		return nil, fmt.Errorf("invalid user id %q: %w", req.UserID, ErrInvalidRating)
	}

	// Check for duplicate review
	var existingID int
	checkQuery := `SELECT id FROM reviews WHERE product_id = $1 AND user_id = $2`
	err = db.QueryRowContext(ctx, checkQuery, productID, userID).Scan(&existingID)
	if err == nil {
		span.SetAttributes(attribute.Bool("review.created", false))
		return nil, fmt.Errorf("create review for product %q: %w", req.ProductID, ErrDuplicateReview)
	} else if err != sql.ErrNoRows {
		span.RecordError(err)
		return nil, fmt.Errorf("check existing review: %w", err)
	}

	// Insert review
	insertQuery := `INSERT INTO reviews (product_id, user_id, rating, title, comment) VALUES ($1, $2, $3, $4, $5) RETURNING id`
	var reviewID int
	err = db.QueryRowContext(ctx, insertQuery, productID, userID, req.Rating, "", req.Comment).Scan(&reviewID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("insert review: %w", err)
	}

	review := &domain.Review{
		ID:        strconv.Itoa(reviewID),
		ProductID: req.ProductID,
		UserID:    req.UserID,
		Rating:    req.Rating,
		Comment:   req.Comment,
	}

	span.SetAttributes(
		attribute.String("review.id", review.ID),
		attribute.Bool("review.created", true),
	)
	span.AddEvent("review.created")

	return review, nil
}
