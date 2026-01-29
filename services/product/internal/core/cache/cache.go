// Package cache provides cache client interface and Valkey implementation
// Following the same pattern as repository interfaces in Core Layer
package cache

import (
	"context"
	"time"
)

// CacheClient defines the interface for cache operations
// Similar to repository pattern - abstraction over cache implementation
type CacheClient interface {
	// Get retrieves a value from cache by key
	// Returns nil, nil if key doesn't exist (cache miss)
	// Returns error if cache operation fails
	Get(ctx context.Context, key string) ([]byte, error)

	// Set stores a value in cache with TTL
	// TTL of 0 means no expiration
	Set(ctx context.Context, key string, value []byte, ttl time.Duration) error

	// SetNX stores a value in cache only if the key does not exist
	// Returns true if the key was set, false otherwise
	SetNX(ctx context.Context, key string, value []byte, ttl time.Duration) (bool, error)

	// Delete removes a key from cache
	Delete(ctx context.Context, key string) error

	// Close closes the cache connection
	Close() error
}
