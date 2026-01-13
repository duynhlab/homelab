// Package v1 provides product review business logic for API version 1.
//
// Error Handling:
// This package defines sentinel errors for review operations.
// These errors should be wrapped with context using fmt.Errorf("%w").
//
// Example Usage:
//
//	if review == nil {
//	    return nil, fmt.Errorf("get review by id %q: %w", reviewID, ErrReviewNotFound)
//	}
//
//	if existingReview != nil {
//	    return nil, fmt.Errorf("create review for product %q by user %q: %w", productID, userID, ErrDuplicateReview)
//	}
package v1

import "errors"

// Sentinel errors for review operations.
var (
	// ErrReviewNotFound indicates the requested review does not exist.
	// HTTP Status: 404 Not Found
	ErrReviewNotFound = errors.New("review not found")

	// ErrDuplicateReview indicates the user has already reviewed this product.
	// HTTP Status: 409 Conflict
	ErrDuplicateReview = errors.New("duplicate review")

	// ErrInvalidRating indicates the rating is outside the valid range (1-5).
	// HTTP Status: 400 Bad Request
	ErrInvalidRating = errors.New("invalid rating")

	// ErrUnauthorized indicates the user is not authorized to perform the operation.
	// HTTP Status: 403 Forbidden
	ErrUnauthorized = errors.New("unauthorized access")
)
