package v2

import (
	"context"

	"github.com/duynhne/monitoring/internal/user/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// UserService defines the business logic interface for user management (v2)
type UserService struct{}

// NewUserService creates a new user service
func NewUserService() *UserService {
	return &UserService{}
}

// GetUser retrieves a user by ID
func (s *UserService) GetUser(ctx context.Context, id string) (*domain.User, error) {
	ctx, span := middleware.StartSpan(ctx, "user.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("user.id", id),
	))
	defer span.End()

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
		attribute.String("api.version", "v2"),
	))
	defer span.End()

	user := &domain.User{
		ID:       "1",
		Username: "current_user_v2",
		Email:    "current@example.com",
		Name:     "Current User V2",
	}

	return user, nil
}

// CreateUser creates a new user
func (s *UserService) CreateUser(ctx context.Context, req domain.CreateUserRequest) (*domain.User, error) {
	ctx, span := middleware.StartSpan(ctx, "user.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("username", req.Username),
		attribute.String("email", req.Email),
	))
	defer span.End()

	user := &domain.User{
		ID:       "new-v2-" + req.Username,
		Username: req.Username,
		Email:    req.Email,
		Name:     req.Name,
	}

	span.SetAttributes(
		attribute.String("user.id", user.ID),
		attribute.Bool("user.created", true),
	)
	span.AddEvent("user.created.v2")

	return user, nil
}

