package v2

import (
	"context"
	"database/sql"
	"fmt"
	"strconv"
	"strings"

	database "github.com/duynhne/monitoring/internal/user/core"
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

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Convert string ID to int
	userID, err := strconv.Atoi(id)
	if err != nil {
		span.SetAttributes(attribute.Bool("user.found", false))
		return nil, fmt.Errorf("invalid user id %q: %w", id, ErrUserNotFound)
	}

	// Query user profile
	var profileID int
	var firstName, lastName sql.NullString
	var phone, address sql.NullString

	query := `SELECT id, user_id, first_name, last_name, phone, address FROM user_profiles WHERE user_id = $1`
	err = db.QueryRowContext(ctx, query, userID).Scan(&profileID, &userID, &firstName, &lastName, &phone, &address)
	if err != nil {
		if err == sql.ErrNoRows {
			span.SetAttributes(attribute.Bool("user.found", false))
			return nil, fmt.Errorf("get user by id %q: %w", id, ErrUserNotFound)
		}
		span.RecordError(err)
		return nil, fmt.Errorf("query user profile: %w", err)
	}

	// Build name
	nameParts := []string{}
	if firstName.Valid && firstName.String != "" {
		nameParts = append(nameParts, firstName.String)
	}
	if lastName.Valid && lastName.String != "" {
		nameParts = append(nameParts, lastName.String)
	}
	name := strings.Join(nameParts, " ")
	if name == "" {
		name = "User " + id
	}

	user := &domain.User{
		ID:       id,
		Username: "user" + id,                  // In production, fetch from auth service
		Email:    "user" + id + "@example.com", // In production, fetch from auth service
		Name:     name,
	}

	span.SetAttributes(attribute.Bool("user.found", true))
	return user, nil
}

// GetProfile retrieves the current user's profile (v2)
func (s *UserService) GetProfile(ctx context.Context) (*domain.User, error) {
	ctx, span := middleware.StartSpan(ctx, "user.profile", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// TODO: Extract user_id from JWT token or session context
	userID := 1

	// Query user profile
	var profileID int
	var firstName, lastName sql.NullString
	var phone, address sql.NullString

	query := `SELECT id, user_id, first_name, last_name, phone, address FROM user_profiles WHERE user_id = $1`
	err := db.QueryRowContext(ctx, query, userID).Scan(&profileID, &userID, &firstName, &lastName, &phone, &address)
	if err != nil {
		if err == sql.ErrNoRows {
			span.SetAttributes(attribute.Bool("profile.found", false))
			return nil, fmt.Errorf("get profile for user %d: %w", userID, ErrUserNotFound)
		}
		span.RecordError(err)
		return nil, fmt.Errorf("query user profile: %w", err)
	}

	// Build name
	nameParts := []string{}
	if firstName.Valid && firstName.String != "" {
		nameParts = append(nameParts, firstName.String)
	}
	if lastName.Valid && lastName.String != "" {
		nameParts = append(nameParts, lastName.String)
	}
	name := strings.Join(nameParts, " ")
	if name == "" {
		name = "User " + strconv.Itoa(userID)
	}

	user := &domain.User{
		ID:       strconv.Itoa(userID),
		Username: "current_user_v2",     // In production, fetch from auth service
		Email:    "current@example.com", // In production, fetch from auth service
		Name:     name,
	}

	span.SetAttributes(attribute.Bool("profile.found", true))
	return user, nil
}

// CreateUser creates a new user profile (v2)
func (s *UserService) CreateUser(ctx context.Context, req domain.CreateUserRequest) (*domain.User, error) {
	ctx, span := middleware.StartSpan(ctx, "user.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("username", req.Username),
		attribute.String("email", req.Email),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Validate email format (v2 enhanced validation)
	if !strings.Contains(req.Email, "@") || !strings.Contains(req.Email, ".") {
		span.SetAttributes(attribute.Bool("user.created", false))
		return nil, fmt.Errorf("validate email %q for user %q: %w", req.Email, req.Username, ErrInvalidEmail)
	}

	// Parse name
	nameParts := strings.Fields(req.Name)
	var firstName, lastName string
	if len(nameParts) > 0 {
		firstName = nameParts[0]
	}
	if len(nameParts) > 1 {
		lastName = strings.Join(nameParts[1:], " ")
	}

	// Mock user_id (in production, should come from auth service)
	userID := len(req.Username) + 100

	// Check if profile exists
	var existingID int
	checkQuery := `SELECT id FROM user_profiles WHERE user_id = $1`
	err := db.QueryRowContext(ctx, checkQuery, userID).Scan(&existingID)
	if err == nil {
		span.SetAttributes(attribute.Bool("user.created", false))
		return nil, fmt.Errorf("create user %q: %w", req.Username, ErrUserExists)
	} else if err != sql.ErrNoRows {
		span.RecordError(err)
		return nil, fmt.Errorf("check existing profile: %w", err)
	}

	// Insert profile
	insertQuery := `INSERT INTO user_profiles (user_id, first_name, last_name) VALUES ($1, $2, $3) RETURNING id`
	var profileID int
	err = db.QueryRowContext(ctx, insertQuery, userID, firstName, lastName).Scan(&profileID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("insert user profile: %w", err)
	}

	user := &domain.User{
		ID:       strconv.Itoa(userID),
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
