// Package v1 provides user management business logic for API version 1.
//
// Error Handling:
// This package defines sentinel errors for user operations.
// These errors should be wrapped with context using fmt.Errorf("%w").
//
// Example Usage:
//
//	if user == nil {
//	    return nil, fmt.Errorf("get user by id %q: %w", userID, ErrUserNotFound)
//	}
//
//	if existingUser != nil {
//	    return nil, fmt.Errorf("create user %q: %w", username, ErrUserExists)
//	}
package v1

import "errors"

// Sentinel errors for user operations.
var (
	// ErrUserNotFound indicates the requested user does not exist.
	// HTTP Status: 404 Not Found
	ErrUserNotFound = errors.New("user not found")

	// ErrUserExists indicates a user with the same username or email already exists.
	// HTTP Status: 409 Conflict
	ErrUserExists = errors.New("user already exists")

	// ErrInvalidEmail indicates the provided email address is invalid.
	// HTTP Status: 400 Bad Request
	ErrInvalidEmail = errors.New("invalid email address")

	// ErrUnauthorized indicates the user is not authorized to perform the operation.
	// HTTP Status: 403 Forbidden
	ErrUnauthorized = errors.New("unauthorized access")
)
