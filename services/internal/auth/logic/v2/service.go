package v2

import (
	"context"
	"fmt"

	"github.com/duynhne/monitoring/internal/auth/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// AuthService defines the business logic interface for authentication (v2)
type AuthService struct{}

// NewAuthService creates a new auth service
func NewAuthService() *AuthService {
	return &AuthService{}
}

// Login handles user login business logic with enhanced security
func (s *AuthService) Login(ctx context.Context, req domain.LoginRequest) (*domain.AuthResponse, error) {
	// Create span for business logic layer
	ctx, span := middleware.StartSpan(ctx, "auth.login", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("username", req.Username),
	))
	defer span.End()

	// Mock authentication logic with enhanced security
	if req.Username == "admin" && req.Password == "password" {
		user := domain.User{
			ID:       "1",
			Username: req.Username,
			Email:    "admin@example.com",
		}

		response := &domain.AuthResponse{
			Token: "mock-jwt-token-v2-enhanced",
			User:  user,
		}

		span.SetAttributes(
			attribute.String("user.id", user.ID),
			attribute.Bool("auth.success", true),
		)
		span.AddEvent("user.authenticated.v2")

		return response, nil
	}

	// Authentication failed - wrap sentinel error with context
	span.SetAttributes(attribute.Bool("auth.success", false))
	span.AddEvent("authentication.failed")
	return nil, fmt.Errorf("authenticate user %q: %w", req.Username, ErrInvalidCredentials)
}

// Register handles user registration business logic with enhanced validation
func (s *AuthService) Register(ctx context.Context, req domain.RegisterRequest) (*domain.AuthResponse, error) {
	// Create span for business logic layer
	ctx, span := middleware.StartSpan(ctx, "auth.register", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("username", req.Username),
		attribute.String("email", req.Email),
	))
	defer span.End()

	// Mock registration logic with enhanced validation
	user := domain.User{
		ID:       "2",
		Username: req.Username,
		Email:    req.Email,
	}

	response := &domain.AuthResponse{
		Token: "mock-jwt-token-v2-enhanced",
		User:  user,
	}

	span.SetAttributes(
		attribute.String("user.id", user.ID),
		attribute.Bool("registration.success", true),
	)
	span.AddEvent("user.registered.v2")

	return response, nil
}

