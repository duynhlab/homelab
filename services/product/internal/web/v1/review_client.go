package v1

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/duynhne/monitoring/services/product/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

// Review represents a review from the review service
type Review struct {
	ID        string  `json:"id"`
	ProductID string  `json:"product_id"`
	UserID    string  `json:"user_id"`
	Rating    int     `json:"rating"`
	Title     string  `json:"title"`
	Comment   string  `json:"comment"`
	CreatedAt *string `json:"created_at,omitempty"`
}

// ReviewClient fetches reviews from the review service
type ReviewClient struct {
	baseURL    string
	httpClient *http.Client
	propagator propagation.TextMapPropagator
}

// NewReviewClient creates a new ReviewClient
func NewReviewClient(baseURL string) *ReviewClient {
	return &ReviewClient{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 3 * time.Second, // 3s timeout for inter-service calls
		},
		propagator: propagation.NewCompositeTextMapPropagator(
			propagation.TraceContext{},
			propagation.Baggage{},
		),
	}
}

// GetProductReviews fetches reviews for a product from the review service
func (c *ReviewClient) GetProductReviews(ctx context.Context, productID string, logger *zap.Logger) ([]Review, error) {
	ctx, span := middleware.StartSpan(ctx, "review_client.get_product_reviews", trace.WithAttributes(
		attribute.String("layer", "web"),
		attribute.String("product.id", productID),
		attribute.String("downstream.service", "review"),
	))
	defer span.End()

	// Build request URL
	reqURL := fmt.Sprintf("%s/api/v1/reviews?product_id=%s", c.baseURL, url.QueryEscape(productID))

	// Create request
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		span.RecordError(err)
		logger.Error("Failed to create request to review service", zap.Error(err))
		return nil, fmt.Errorf("create request: %w", err)
	}

	// Inject trace context headers for distributed tracing
	c.propagator.Inject(ctx, propagation.HeaderCarrier(req.Header))

	// Make the request
	span.SetAttributes(attribute.String("http.url", reqURL))
	resp, err := c.httpClient.Do(req)
	if err != nil {
		span.RecordError(err)
		span.SetAttributes(attribute.Bool("review_service.available", false))
		logger.Error("Failed to call review service", zap.Error(err), zap.String("url", reqURL))
		return nil, fmt.Errorf("call review service: %w", err)
	}
	defer resp.Body.Close()

	span.SetAttributes(
		attribute.Int("http.status_code", resp.StatusCode),
		attribute.Bool("review_service.available", true),
	)

	// Handle non-2xx responses
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		err := fmt.Errorf("review service returned status %d: %s", resp.StatusCode, string(body))
		span.RecordError(err)
		logger.Warn("Review service returned non-OK status",
			zap.Int("status", resp.StatusCode),
			zap.String("body", string(body)),
		)
		return nil, err
	}

	// Parse response
	var reviews []Review
	if err := json.NewDecoder(resp.Body).Decode(&reviews); err != nil {
		span.RecordError(err)
		logger.Error("Failed to decode review service response", zap.Error(err))
		return nil, fmt.Errorf("decode response: %w", err)
	}

	span.SetAttributes(attribute.Int("reviews.count", len(reviews)))
	logger.Debug("Fetched reviews from review service",
		zap.String("product_id", productID),
		zap.Int("count", len(reviews)),
	)

	return reviews, nil
}

// ComputeReviewsSummary computes total and average rating from reviews
func ComputeReviewsSummary(reviews []Review) (total int, averageRating float64) {
	total = len(reviews)
	if total == 0 {
		return 0, 0.0
	}

	sum := 0
	for _, r := range reviews {
		sum += r.Rating
	}
	averageRating = float64(sum) / float64(total)
	return total, averageRating
}

// reviewClient is the singleton instance, set via SetReviewClient
var reviewClient *ReviewClient

// SetReviewClient sets the review client instance
func SetReviewClient(client *ReviewClient) {
	reviewClient = client
}
