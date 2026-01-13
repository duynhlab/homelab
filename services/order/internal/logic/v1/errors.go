// Package v1 provides order management business logic for API version 1.
//
// Error Handling:
// This package defines sentinel errors for order operations.
// These errors should be wrapped with context using fmt.Errorf("%w").
//
// Example Usage:
//
//	if order == nil {
//	    return nil, fmt.Errorf("get order by id %q: %w", orderID, ErrOrderNotFound)
//	}
//
//	if order.Status != "pending" {
//	    return nil, fmt.Errorf("cancel order %q: %w", orderID, ErrInvalidOrderState)
//	}
package v1

import "errors"

// Sentinel errors for order operations.
var (
	// ErrOrderNotFound indicates the requested order does not exist.
	// HTTP Status: 404 Not Found
	ErrOrderNotFound = errors.New("order not found")

	// ErrInvalidOrderState indicates the order is in an invalid state for the requested operation.
	// HTTP Status: 400 Bad Request
	ErrInvalidOrderState = errors.New("invalid order state")

	// ErrInvalidOrder is an alias for ErrInvalidOrderState (backward compatibility)
	ErrInvalidOrder = ErrInvalidOrderState

	// ErrPaymentFailed indicates the payment processing failed.
	// HTTP Status: 402 Payment Required
	ErrPaymentFailed = errors.New("payment failed")

	// ErrUnauthorized indicates the user is not authorized to access the order.
	// HTTP Status: 403 Forbidden
	ErrUnauthorized = errors.New("unauthorized access")
)
