package v1

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"go.uber.org/zap"
)

// CartClient handles HTTP calls to the cart service
type CartClient struct {
	baseURL    string
	httpClient *http.Client
}

func NewCartClient(baseURL string) *CartClient {
	return &CartClient{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 3 * time.Second,
		},
	}
}

// ClearCart clears the authenticated user's cart by calling cart service.
// It forwards the original Authorization header to preserve identity.
func (c *CartClient) ClearCart(ctx context.Context, authHeader string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, c.baseURL+"/api/v1/cart", nil)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	if authHeader != "" {
		req.Header.Set("Authorization", authHeader)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("request cart service: %w", err)
	}
	defer resp.Body.Close()

	// Treat any non-2xx as error (best-effort caller decides what to do)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("cart service returned status %d", resp.StatusCode)
	}
	return nil
}

// Global cart client (set during init)
var cartClient *CartClient

func SetCartClient(client *CartClient) {
	cartClient = client
}

func getCartClient(logger *zap.Logger) *CartClient {
	if cartClient == nil && logger != nil {
		logger.Warn("Cart client not initialized")
	}
	return cartClient
}

