// Package v1 provides product catalog business logic for API version 1.
//
// Error Handling:
// This package defines sentinel errors for product operations.
// These errors should be wrapped with context using fmt.Errorf("%w").
//
// Example Usage:
//
//	if product == nil {
//	    return nil, fmt.Errorf("get product by id %q: %w", productID, ErrProductNotFound)
//	}
//
//	if product.Stock < quantity {
//	    return nil, fmt.Errorf("check stock for product %q: %w", productID, ErrInsufficientStock)
//	}
package v1

import "errors"

// Sentinel errors for product operations.
var (
	// ErrProductNotFound indicates the requested product does not exist.
	// HTTP Status: 404 Not Found
	ErrProductNotFound = errors.New("product not found")

	// ErrInsufficientStock indicates there is not enough inventory to fulfill the request.
	// HTTP Status: 400 Bad Request
	ErrInsufficientStock = errors.New("insufficient stock")

	// ErrInvalidPrice indicates the provided price is invalid (e.g., negative).
	// HTTP Status: 400 Bad Request
	ErrInvalidPrice = errors.New("invalid price")

	// ErrUnauthorized indicates the user is not authorized to perform the operation.
	// HTTP Status: 403 Forbidden
	ErrUnauthorized = errors.New("unauthorized access")
)
