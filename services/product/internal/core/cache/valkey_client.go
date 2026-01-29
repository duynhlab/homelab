// Package cache provides Valkey (Redis-compatible) cache client implementation
package cache

import (
	"context"
	"time"

	"github.com/redis/go-redis/v9"
)

// ValkeyCacheClient implements CacheClient interface using Valkey/Redis
type ValkeyCacheClient struct {
	client *redis.Client
}

// NewValkeyCacheClient creates a new Valkey cache client
func NewValkeyCacheClient(addr string, password string, db int) (*ValkeyCacheClient, error) {
	client := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: password,
		DB:       db,
	})

	// Test connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := client.Ping(ctx).Err(); err != nil {
		return nil, err
	}

	return &ValkeyCacheClient{
		client: client,
	}, nil
}

// Get retrieves a value from cache by key
func (c *ValkeyCacheClient) Get(ctx context.Context, key string) ([]byte, error) {
	val, err := c.client.Get(ctx, key).Bytes()
	if err == redis.Nil {
		// Key doesn't exist - cache miss (not an error)
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return val, nil
}

// Set stores a value in cache with TTL
func (c *ValkeyCacheClient) Set(ctx context.Context, key string, value []byte, ttl time.Duration) error {
	return c.client.Set(ctx, key, value, ttl).Err()
}

// SetNX stores a value in cache only if the key does not exist
func (c *ValkeyCacheClient) SetNX(ctx context.Context, key string, value []byte, ttl time.Duration) (bool, error) {
	return c.client.SetNX(ctx, key, value, ttl).Result()
}

// Delete removes a key from cache
func (c *ValkeyCacheClient) Delete(ctx context.Context, key string) error {
	return c.client.Del(ctx, key).Err()
}

// Close closes the cache connection
func (c *ValkeyCacheClient) Close() error {
	return c.client.Close()
}
