// Package v1 provides shipping business logic for API version 1.
//
// Error Handling:
// This package defines sentinel errors for shipping operations.
// These errors should be wrapped with context using fmt.Errorf("%w").
//
// Example Usage:
//
//	if shipment == nil {
//	    return nil, fmt.Errorf("get shipment by id %q: %w", shipmentID, ErrShipmentNotFound)
//	}
//
//	if !isValidAddress(address) {
//	    return nil, fmt.Errorf("create shipment with address %q: %w", address, ErrInvalidAddress)
//	}
package v1

import "errors"

// Sentinel errors for shipping operations.
var (
	// ErrShipmentNotFound indicates the requested shipment does not exist.
	// HTTP Status: 404 Not Found
	ErrShipmentNotFound = errors.New("shipment not found")

	// ErrInvalidAddress indicates the shipping address is invalid or incomplete.
	// HTTP Status: 400 Bad Request
	ErrInvalidAddress = errors.New("invalid address")

	// ErrCarrierUnavailable indicates the shipping carrier is unavailable.
	// HTTP Status: 503 Service Unavailable
	ErrCarrierUnavailable = errors.New("carrier unavailable")

	// ErrUnauthorized indicates the user is not authorized to perform the operation.
	// HTTP Status: 403 Forbidden
	ErrUnauthorized = errors.New("unauthorized access")
)
