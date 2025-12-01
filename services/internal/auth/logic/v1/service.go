package v1

import (
	"context"

	"github.com/duynhne/monitoring/internal/auth/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// AuthService defines the business logic interface for authentication
type AuthService struct{}

// NewAuthService creates a new auth service
func NewAuthService() *AuthService {
	return &AuthService{}
}

// Login handles user login business logic
func (s *AuthService) Login(ctx context.Context, req domain.LoginRequest) (*domain.AuthResponse, error) {
	// Create span for business logic layer
	ctx, span := middleware.StartSpan(ctx, "auth.login", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("username", req.Username),
	))
	defer span.End()

	// Mock authentication logic
	if req.Username == "admin" && req.Password == "password" {
		user := domain.User{
			ID:       "1",
			Username: req.Username,
			Email:    "admin@example.com",
		}

		response := &domain.AuthResponse{
			Token: "mock-jwt-token-v1",
			User:  user,
		}

		span.SetAttributes(
			attribute.String("user.id", user.ID),
			attribute.Bool("auth.success", true),
		)
		span.AddEvent("user.authenticated")

		return response, nil
	}

	span.SetAttributes(attribute.Bool("auth.success", false))
	span.AddEvent("authentication.failed")
	return nil, &AuthError{Message: "Invalid credentials", Code: "INVALID_CREDENTIALS"}
}

// Register handles user registration business logic
func (s *AuthService) Register(ctx context.Context, req domain.RegisterRequest) (*domain.AuthResponse, error) {
	// Create span for business logic layer
	ctx, span := middleware.StartSpan(ctx, "auth.register", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("username", req.Username),
		attribute.String("email", req.Email),
	))
	defer span.End()

	// Mock registration logic
	user := domain.User{
		ID:       "2",
		Username: req.Username,
		Email:    req.Email,
	}

	response := &domain.AuthResponse{
		Token: "mock-jwt-token-v1",
		User:  user,
	}

	span.SetAttributes(
		attribute.String("user.id", user.ID),
		attribute.Bool("registration.success", true),
	)
	span.AddEvent("user.registered")

	return response, nil
}

// AuthError represents an authentication error
type AuthError struct {
	Message string
	Code    string
}

func (e *AuthError) Error() string {
	return e.Message
}

