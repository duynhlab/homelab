// Package cache provides Product-specific cache wrapper
// Handles cache key generation and JSON serialization/deserialization
package cache

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/duynhne/monitoring/services/product/internal/core/domain"
)

// ProductCache wraps CacheClient with Product-specific operations
type ProductCache struct {
	client    CacheClient
	ttlList   time.Duration
	ttlDetail time.Duration
}

// NewProductCache creates a new ProductCache wrapper
func NewProductCache(client CacheClient, ttlList, ttlDetail time.Duration) *ProductCache {
	return &ProductCache{
		client:    client,
		ttlList:   ttlList,
		ttlDetail: ttlDetail,
	}
}

// generateProductKey generates cache key for a single product
func (c *ProductCache) generateProductKey(id string) string {
	return fmt.Sprintf("product:%s", id)
}

// generateProductListKey generates cache key for product list with filters
func (c *ProductCache) generateProductListKey(filters domain.ProductFilters) string {
	// Normalize filters for consistent key generation
	category := filters.Category
	if category == "" {
		category = "all"
	}
	search := filters.Search
	if search == "" {
		search = "none"
	}
	sortBy := filters.SortBy
	if sortBy == "" {
		sortBy = "created_at"
	}
	order := filters.Order
	if order == "" {
		order = "desc"
	}
	page := filters.Page
	if page == 0 {
		page = 1
	}
	limit := filters.Limit
	if limit == 0 {
		limit = 20
	}

	return fmt.Sprintf("product:list:%s:%s:%s:%s:%d:%d", category, search, sortBy, order, page, limit)
}

// GetProduct retrieves a single product from cache
// Returns nil, nil if cache miss (not an error)
func (c *ProductCache) GetProduct(ctx context.Context, id string) (*domain.Product, error) {
	key := c.generateProductKey(id)
	data, err := c.client.Get(ctx, key)
	if err != nil {
		return nil, err
	}
	if data == nil {
		// Cache miss
		return nil, nil
	}

	var product domain.Product
	if err := json.Unmarshal(data, &product); err != nil {
		return nil, fmt.Errorf("failed to unmarshal cached product: %w", err)
	}

	return &product, nil
}

// SetProduct stores a single product in cache
func (c *ProductCache) SetProduct(ctx context.Context, id string, product *domain.Product) error {
	key := c.generateProductKey(id)
	data, err := json.Marshal(product)
	if err != nil {
		return fmt.Errorf("failed to marshal product: %w", err)
	}

	return c.client.Set(ctx, key, data, c.ttlDetail)
}

// GetProductOrSet retrieves a product from cache or fetches it using the provided function
// Implements Cache Stampede Prevention using distributed locking
func (c *ProductCache) GetProductOrSet(ctx context.Context, id string, fetchFunc func() (*domain.Product, error)) (*domain.Product, error) {
	// 1. Check cache first
	product, err := c.GetProduct(ctx, id)
	if err != nil {
		return nil, err
	}
	if product != nil {
		return product, nil
	}

	// 2. Cache miss - Try to acquire lock
	lockKey := fmt.Sprintf("lock:product:%s", id)
	acquired, err := c.client.SetNX(ctx, lockKey, []byte("1"), 5*time.Second) // 5s lock TTL
	if err != nil {
		return nil, err
	}

	if acquired {
		// 3a. Lock acquired - Owner responsible for fetching data
		defer c.client.Delete(ctx, lockKey) // Ensure lock is released

		// Fetch from DB
		product, err := fetchFunc()
		if err != nil {
			return nil, err
		}

		// Set cache
		if err := c.SetProduct(ctx, id, product); err != nil {
			// Log error but return success since we have the data
			// In a real app, use a logger here
		}

		return product, nil
	} else {
		// 3b. Lock failed - Wait and retry (spin lock)
		// Wait for data to appear in cache (max 10 retries, 500ms total)
		ticker := time.NewTicker(50 * time.Millisecond)
		defer ticker.Stop()

		timeout := time.After(500 * time.Millisecond)

		for {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-timeout:
				// Timeout waiting for lock/data - Fallback to DB (or return error)
				// Here we fallback to DB to ensure availability
				return fetchFunc()
			case <-ticker.C:
				// Check cache again
				product, err := c.GetProduct(ctx, id)
				if err != nil {
					continue // Retry on error
				}
				if product != nil {
					return product, nil
				}
			}
		}
	}
}

// GetProductList retrieves product list from cache
// Returns nil, 0, nil if cache miss (not an error)
func (c *ProductCache) GetProductList(ctx context.Context, filters domain.ProductFilters) ([]domain.Product, int, error) {
	key := c.generateProductListKey(filters)
	data, err := c.client.Get(ctx, key)
	if err != nil {
		return nil, 0, err
	}
	if data == nil {
		// Cache miss
		return nil, 0, nil
	}

	var result struct {
		Products []domain.Product `json:"products"`
		Total    int              `json:"total"`
	}
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, 0, fmt.Errorf("failed to unmarshal cached product list: %w", err)
	}

	return result.Products, result.Total, nil
}

// SetProductList stores product list in cache
func (c *ProductCache) SetProductList(ctx context.Context, filters domain.ProductFilters, products []domain.Product, total int) error {
	key := c.generateProductListKey(filters)
	result := struct {
		Products []domain.Product `json:"products"`
		Total    int              `json:"total"`
	}{
		Products: products,
		Total:    total,
	}

	data, err := json.Marshal(result)
	if err != nil {
		return fmt.Errorf("failed to marshal product list: %w", err)
	}

	return c.client.Set(ctx, key, data, c.ttlList)
}

// InvalidateProduct deletes a single product from cache
func (c *ProductCache) InvalidateProduct(ctx context.Context, id string) error {
	key := c.generateProductKey(id)
	return c.client.Delete(ctx, key)
}

// InvalidateProductList deletes all product list cache keys
// Note: This is a simple implementation that deletes common patterns
// For production, consider using Redis SCAN or maintaining a key index
func (c *ProductCache) InvalidateProductList(ctx context.Context) error {
	// For now, we'll delete specific common patterns
	// A more sophisticated implementation would use Redis SCAN
	commonKeys := []string{
		"product:list:all:none:created_at:desc:1:20",
		"product:list:all:none:created_at:desc:1:30",
		"product:list:all:none:price:asc:1:20",
		"product:list:all:none:price:desc:1:20",
	}

	for _, key := range commonKeys {
		_ = c.client.Delete(ctx, key) // Ignore errors for non-existent keys
	}

	// TODO: Implement proper pattern matching using Redis SCAN if needed
	// For now, this simple approach works for learning purposes
	return nil
}
