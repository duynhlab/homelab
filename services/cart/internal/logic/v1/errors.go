// Package v1 provides shopping cart business logic for API version 1.
//
// Error Handling:
// This package defines sentinel errors for cart operations.
// These errors should be wrapped with context using fmt.Errorf("%w").
//
// Example Usage:
//
//	if cart == nil {
//	    return nil, fmt.Errorf("get cart by id %q: %w", cartID, ErrCartNotFound)
//	}
//
//	if len(cart.Items) == 0 {
//	    return nil, fmt.Errorf("checkout cart %q: %w", cartID, ErrCartEmpty)
//	}
package v1

import "errors"

// Sentinel errors for cart operations.
var (
	// ErrCartNotFound indicates the requested shopping cart does not exist.
	// HTTP Status: 404 Not Found
	ErrCartNotFound = errors.New("cart not found")

	// ErrCartEmpty indicates the cart contains no items.
	// HTTP Status: 400 Bad Request
	ErrCartEmpty = errors.New("cart is empty")

	// ErrItemNotInCart indicates the specified item is not in the cart.
	// HTTP Status: 404 Not Found
	ErrItemNotInCart = errors.New("item not in cart")

	// ErrInvalidQuantity indicates the provided quantity is invalid (e.g., zero or negative).
	// HTTP Status: 400 Bad Request
	ErrInvalidQuantity = errors.New("invalid quantity")

	// ErrCartItemNotFound indicates the specified cart item does not exist.
	// HTTP Status: 404 Not Found
	ErrCartItemNotFound = errors.New("cart item not found")

	// ErrInsufficientStock indicates there is not enough stock for the requested quantity.
	// HTTP Status: 400 Bad Request
	ErrInsufficientStock = errors.New("insufficient stock")

	// ErrUnauthorized indicates the user is not authorized to access the cart.
	// HTTP Status: 403 Forbidden
	ErrUnauthorized = errors.New("unauthorized access")
)
