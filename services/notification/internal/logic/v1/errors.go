// Package v1 provides notification business logic for API version 1.
//
// Error Handling:
// This package defines sentinel errors for notification operations.
// These errors should be wrapped with context using fmt.Errorf("%w").
//
// Example Usage:
//
//	if notification == nil {
//	    return nil, fmt.Errorf("get notification by id %q: %w", notificationID, ErrNotificationNotFound)
//	}
//
//	if !isValidEmail(recipient) {
//	    return nil, fmt.Errorf("send notification to %q: %w", recipient, ErrInvalidRecipient)
//	}
package v1

import "errors"

// Sentinel errors for notification operations.
var (
	// ErrNotificationNotFound indicates the requested notification does not exist.
	// HTTP Status: 404 Not Found
	ErrNotificationNotFound = errors.New("notification not found")

	// ErrInvalidRecipient indicates the recipient address is invalid.
	// HTTP Status: 400 Bad Request
	ErrInvalidRecipient = errors.New("invalid recipient")

	// ErrDeliveryFailed indicates the notification delivery failed.
	// HTTP Status: 500 Internal Server Error
	ErrDeliveryFailed = errors.New("delivery failed")

	// ErrUnauthorized indicates the user is not authorized to perform the operation.
	// HTTP Status: 403 Forbidden
	ErrUnauthorized = errors.New("unauthorized access")
)
