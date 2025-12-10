package v1

import (
	"context"
	"fmt"

	"github.com/duynhne/monitoring/internal/user/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// UserService defines the business logic interface for user management
type UserService struct{}

// NewUserService creates a new user service
func NewUserService() *UserService {
	return &UserService{}
}

// GetUser retrieves a user by ID
func (s *UserService) GetUser(ctx context.Context, id string) (*domain.User, error) {
	ctx, span := middleware.StartSpan(ctx, "user.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("user.id", id),
	))
	defer span.End()

	// Mock logic: simulate user not found for id "999"
	if id == "999" {
		span.SetAttributes(attribute.Bool("user.found", false))
		return nil, fmt.Errorf("get user by id %q: %w", id, ErrUserNotFound)
	}

	user := &domain.User{
		ID:       id,
		Username: "user" + id,
		Email:    "user" + id + "@example.com",
		Name:     "User " + id,
	}

	span.SetAttributes(attribute.Bool("user.found", true))
	return user, nil
}

// GetProfile retrieves the current user's profile
func (s *UserService) GetProfile(ctx context.Context) (*domain.User, error) {
	ctx, span := middleware.StartSpan(ctx, "user.profile", trace.WithAttributes(
		attribute.String("layer", "logic"),
	))
	defer span.End()

	user := &domain.User{
		ID:       "1",
		Username: "current_user",
		Email:    "current@example.com",
		Name:     "Current User",
	}

	return user, nil
}

// CreateUser creates a new user
func (s *UserService) CreateUser(ctx context.Context, req domain.CreateUserRequest) (*domain.User, error) {
	ctx, span := middleware.StartSpan(ctx, "user.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("username", req.Username),
		attribute.String("email", req.Email),
	))
	defer span.End()

	// Mock logic: simulate duplicate user for username "duplicate"
	if req.Username == "duplicate" {
		span.SetAttributes(attribute.Bool("user.created", false))
		return nil, fmt.Errorf("create user %q: %w", req.Username, ErrUserExists)
	}

	// Mock logic: validate email
	if req.Email == "invalid" {
		span.SetAttributes(attribute.Bool("user.created", false))
		return nil, fmt.Errorf("validate email %q for user %q: %w", req.Email, req.Username, ErrInvalidEmail)
	}

	user := &domain.User{
		ID:       "new-" + req.Username,
		Username: req.Username,
		Email:    req.Email,
		Name:     req.Name,
	}

	span.SetAttributes(
		attribute.String("user.id", user.ID),
		attribute.Bool("user.created", true),
	)
	span.AddEvent("user.created")

	return user, nil
}

