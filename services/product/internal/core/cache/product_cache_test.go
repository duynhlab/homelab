package cache

import (
	"context"
	"encoding/json"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/duynhne/monitoring/services/product/internal/core/domain"
)

// MockCacheClient for testing
type MockCacheClient struct {
	data      map[string][]byte
	locks     map[string]bool
	mu        sync.Mutex
	setNXCall int32
}

func NewMockCacheClient() *MockCacheClient {
	return &MockCacheClient{
		data:  make(map[string][]byte),
		locks: make(map[string]bool),
	}
}

func (m *MockCacheClient) Get(ctx context.Context, key string) ([]byte, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if val, ok := m.data[key]; ok {
		return val, nil
	}
	return nil, nil
}

func (m *MockCacheClient) Set(ctx context.Context, key string, value []byte, ttl time.Duration) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.data[key] = value
	return nil
}

func (m *MockCacheClient) SetNX(ctx context.Context, key string, value []byte, ttl time.Duration) (bool, error) {
	atomic.AddInt32(&m.setNXCall, 1)
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.locks[key] {
		return false, nil
	}
	m.locks[key] = true
	return true, nil
}

func (m *MockCacheClient) Delete(ctx context.Context, key string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.data, key)
	delete(m.locks, key) // Also release lock if deleting key (simplified)
	return nil
}

func (m *MockCacheClient) Close() error {
	return nil
}

// TestGetProductOrSet_StampedePrevention verifies that multiple concurrent calls
// only trigger a single DB fetch
func TestGetProductOrSet_StampedePrevention(t *testing.T) {
	mockClient := NewMockCacheClient()
	productCache := NewProductCache(mockClient, 5*time.Minute, 10*time.Minute)
	ctx := context.Background()
	productID := "123"

	// Counter for DB fetch calls
	var dbFetchCalls int32

	// Simulated DB fetch function
	fetchFunc := func() (*domain.Product, error) {
		atomic.AddInt32(&dbFetchCalls, 1)
		time.Sleep(100 * time.Millisecond) // Simulate DB latency
		return &domain.Product{
			ID:   productID,
			Name: "Test Product",
		}, nil
	}

	// Concurrent requests
	concurrency := 10
	var wg sync.WaitGroup
	wg.Add(concurrency)

	start := time.Now()
	for i := 0; i < concurrency; i++ {
		go func() {
			defer wg.Done()
			product, err := productCache.GetProductOrSet(ctx, productID, fetchFunc)
			if err != nil {
				t.Errorf("GetProductOrSet failed: %v", err)
			}
			if product == nil || product.ID != productID {
				t.Errorf("Expected product ID %s, got %v", productID, product)
			}
		}()
	}

	wg.Wait()
	duration := time.Since(start)

	// Verification
	calls := atomic.LoadInt32(&dbFetchCalls)
	if calls != 1 {
		t.Errorf("Stampede Prevention FAILED: Expected 1 DB fetch, got %d", calls)
	} else {
		t.Logf("Stampede Prevention PASSED: %d concurrent requests -> %d DB fetch", concurrency, calls)
	}

	t.Logf("Total time: %v", duration)
}

// TestGetProductOrSet_CacheHit verifies cache hit behavior
func TestGetProductOrSet_CacheHit(t *testing.T) {
	mockClient := NewMockCacheClient()
	productCache := NewProductCache(mockClient, 5*time.Minute, 10*time.Minute)
	ctx := context.Background()
	productID := "123"

	// Pre-populate cache
	product := &domain.Product{ID: productID, Name: "Cached Product"}
	data, _ := json.Marshal(product)
	mockClient.Set(ctx, "product:"+productID, data, 0)

	// Fetch
	dbFetchCalls := 0
	fetchFunc := func() (*domain.Product, error) {
		dbFetchCalls++
		return nil, errors.New("should not be called")
	}

	p, err := productCache.GetProductOrSet(ctx, productID, fetchFunc)
	if err != nil {
		t.Fatalf("Failed to get product: %v", err)
	}

	if p.Name != "Cached Product" {
		t.Errorf("Expected 'Cached Product', got '%s'", p.Name)
	}
	if dbFetchCalls != 0 {
		t.Errorf("Expected 0 DB fetches, got %d", dbFetchCalls)
	}
}
