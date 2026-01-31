package middleware

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// AuthUser represents the user info returned from auth service
type AuthUser struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	Email    string `json:"email"`
}

// AuthClient handles communication with the auth service
type AuthClient struct {
	baseURL    string
	httpClient *http.Client
}

// NewAuthClient creates a new auth client
func NewAuthClient(baseURL string) *AuthClient {
	return &AuthClient{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

// GetMe retrieves user info from auth service using the token
func (c *AuthClient) GetMe(token string) (*AuthUser, error) {
	req, err := http.NewRequest("GET", c.baseURL+"/api/v1/auth/me", nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request auth service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusUnauthorized {
		return nil, fmt.Errorf("invalid or expired token")
	}
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("auth service error: %d - %s", resp.StatusCode, string(body))
	}

	var user AuthUser
	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}

	return &user, nil
}

// AuthMiddleware creates a middleware that validates tokens via auth service
// It sets "user_id", "username", "email" in the gin context if authentication succeeds.
// When allowUnauthenticatedFallback is true (demo mode), missing/invalid tokens fall back to user_id="1".
// When false (default), returns 401 for missing or invalid tokens.
func AuthMiddleware(authClient *AuthClient, logger *zap.Logger, allowUnauthenticatedFallback bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Get token from Authorization header
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			if allowUnauthenticatedFallback {
				c.Set("user_id", "1")
				c.Next()
				return
			}
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
			return
		}

		// Extract token from "Bearer <token>"
		const bearerPrefix = "Bearer "
		if len(authHeader) <= len(bearerPrefix) || authHeader[:len(bearerPrefix)] != bearerPrefix {
			if allowUnauthenticatedFallback {
				c.Set("user_id", "1")
				c.Next()
				return
			}
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Invalid authorization header"})
			return
		}
		token := authHeader[len(bearerPrefix):]

		// Call auth service to validate token
		user, err := authClient.GetMe(token)
		if err != nil {
			if logger != nil {
				logger.Debug("Auth validation failed", zap.Error(err))
			}
			if allowUnauthenticatedFallback {
				c.Set("user_id", "1")
				c.Next()
				return
			}
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired token"})
			return
		}

		// Set user info in context for handlers to use
		c.Set("user_id", user.ID)
		c.Set("username", user.Username)
		c.Set("email", user.Email)
		c.Next()
	}
}
