package v1

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
	database "github.com/duynhne/monitoring/services/review/internal/core"
	"github.com/duynhne/monitoring/services/review/internal/core/domain"
	"github.com/duynhne/monitoring/services/review/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type ReviewService struct{}

func NewReviewService() *ReviewService {
	return &ReviewService{}
}

func (s *ReviewService) ListReviews(ctx context.Context, productID string) ([]domain.Review, error) {
	ctx, span := middleware.StartSpan(ctx, "review.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.id", productID),
	))
	defer span.End()

	// Get database connection pool (pgx)
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Convert productID to int
	prodID, err := strconv.Atoi(productID)
	if err != nil {
		return nil, fmt.Errorf("invalid product_id %q: %w", productID, err)
	}

	// Query reviews filtered by product_id
	query := `SELECT id, product_id, user_id, rating, title, comment, created_at FROM reviews WHERE product_id = $1 ORDER BY created_at DESC`
	rows, err := db.Query(ctx, query, prodID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("query reviews: %w", err)
	}
	defer rows.Close()

	var reviews []domain.Review
	for rows.Next() {
		var reviewID, dbProductID, userID int
		var rating int
		var title, comment *string // Use pointers for nullable columns
		var createdAt *time.Time

		err := rows.Scan(&reviewID, &dbProductID, &userID, &rating, &title, &comment, &createdAt)
		if err != nil {
			span.RecordError(err)
			continue
		}

		review := domain.Review{
			ID:        strconv.Itoa(reviewID),
			ProductID: strconv.Itoa(dbProductID),
			UserID:    strconv.Itoa(userID),
			Rating:    rating,
			CreatedAt: createdAt,
		}
		if title != nil {
			review.Title = *title
		}
		if comment != nil {
			review.Comment = *comment
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

	// Get database connection pool (pgx)
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
	err = db.QueryRow(ctx, checkQuery, productID, userID).Scan(&existingID)
	if err == nil {
		span.SetAttributes(attribute.Bool("review.created", false))
		return nil, fmt.Errorf("create review for product %q: %w", req.ProductID, ErrDuplicateReview)
	} else if !errors.Is(err, pgx.ErrNoRows) {
		span.RecordError(err)
		return nil, fmt.Errorf("check existing review: %w", err)
	}

	// Insert review and return id + created_at
	insertQuery := `INSERT INTO reviews (product_id, user_id, rating, title, comment) VALUES ($1, $2, $3, $4, $5) RETURNING id, created_at`
	var reviewID int
	var createdAt time.Time
	err = db.QueryRow(ctx, insertQuery, productID, userID, req.Rating, req.Title, req.Comment).Scan(&reviewID, &createdAt)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("insert review: %w", err)
	}

	review := &domain.Review{
		ID:        strconv.Itoa(reviewID),
		ProductID: req.ProductID,
		UserID:    req.UserID,
		Rating:    req.Rating,
		Title:     req.Title,
		Comment:   req.Comment,
		CreatedAt: &createdAt,
	}

	span.SetAttributes(
		attribute.String("review.id", review.ID),
		attribute.Bool("review.created", true),
	)
	span.AddEvent("review.created")

	return review, nil
}
