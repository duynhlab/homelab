// Package v1 provides authentication business logic for API version 1.
//
// Error Handling:
// This package defines sentinel errors that represent common authentication failures.
// These errors should be wrapped with context using fmt.Errorf("%w") when returned
// from business logic methods.
//
// Example Usage:
//
//	if user == nil {
//	    return nil, fmt.Errorf("authenticate user %q: %w", username, ErrUserNotFound)
//	}
//
//	if !isValidPassword(user.PasswordHash, password) {
//	    return nil, fmt.Errorf("authenticate user %q: %w", username, ErrInvalidCredentials)
//	}
//
// Error Checking (in handlers):
//
//	switch {
//	case errors.Is(err, logicv1.ErrInvalidCredentials):
//	    c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid username or password"})
//	case errors.Is(err, logicv1.ErrUserNotFound):
//	    c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid username or password"})
//	default:
//	    c.JSON(http.StatusInternalServerError, gin.H{"error": "Internal server error"})
//	}
package v1

import "errors"

// Sentinel errors for authentication operations.
// These errors should be wrapped with context using fmt.Errorf("%w") when returned.
var (
	// ErrInvalidCredentials indicates the provided credentials are incorrect.
	// HTTP Status: 401 Unauthorized
	ErrInvalidCredentials = errors.New("invalid credentials")

	// ErrUserNotFound indicates the user does not exist in the system.
	// HTTP Status: 401 Unauthorized (don't reveal user existence)
	ErrUserNotFound = errors.New("user not found")

	// ErrPasswordExpired indicates the user's password has expired and must be reset.
	// HTTP Status: 403 Forbidden
	ErrPasswordExpired = errors.New("password expired")

	// ErrAccountLocked indicates the user's account is locked due to security reasons.
	// HTTP Status: 403 Forbidden
	ErrAccountLocked = errors.New("account locked")

	// ErrUnauthorized indicates the user is not authorized to perform the operation.
	// HTTP Status: 403 Forbidden
	ErrUnauthorized = errors.New("unauthorized access")

	// ErrUserExists indicates the username or email already exists in the system.
	// HTTP Status: 409 Conflict
	ErrUserExists = errors.New("user already exists")

	// ErrSessionNotFound indicates the session token does not exist.
	// HTTP Status: 401 Unauthorized
	ErrSessionNotFound = errors.New("session not found")

	// ErrSessionExpired indicates the session token has expired.
	// HTTP Status: 401 Unauthorized
	ErrSessionExpired = errors.New("session expired")
)
