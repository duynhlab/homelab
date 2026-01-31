package v1

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
	database "github.com/duynhne/monitoring/services/user/internal/core"
	"github.com/duynhne/monitoring/services/user/internal/core/domain"
	"github.com/duynhne/monitoring/services/user/middleware"
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
// userID, username, email are passed from auth middleware (auth service token introspection)
func (s *UserService) GetProfile(ctx context.Context, userID string, username, email string) (*domain.User, error) {
	ctx, span := middleware.StartSpan(ctx, "user.profile", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("user.id", userID),
	))
	defer span.End()

	// Get database connection pool (pgx)
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Parse user_id for database query
	uid, err := strconv.Atoi(userID)
	if err != nil {
		span.SetAttributes(attribute.Bool("profile.found", false))
		return nil, fmt.Errorf("invalid user_id %q: %w", userID, ErrUserNotFound)
	}

	// Query user profile - use pointers for nullable columns
	var profileID int
	var firstName, lastName, phone, address *string

	query := `SELECT id, user_id, first_name, last_name, phone, address FROM user_profiles WHERE user_id = $1`
	err = db.QueryRow(ctx, query, uid).Scan(&profileID, &uid, &firstName, &lastName, &phone, &address)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			span.SetAttributes(attribute.Bool("profile.found", false))
			// Return auth data even if no profile in user_profiles (e.g., new user)
			return &domain.User{
				ID:       userID,
				Username: username,
				Email:    email,
				Name:     "User " + userID,
			}, nil
		}
		span.RecordError(err)
		return nil, fmt.Errorf("query user profile: %w", err)
	}

	// Build name from profile
	nameParts := []string{}
	if firstName != nil && *firstName != "" {
		nameParts = append(nameParts, *firstName)
	}
	if lastName != nil && *lastName != "" {
		nameParts = append(nameParts, *lastName)
	}
	name := strings.Join(nameParts, " ")
	if name == "" {
		name = "User " + userID
	}

	// Build phone string
	phoneStr := ""
	if phone != nil && *phone != "" {
		phoneStr = *phone
	}

	user := &domain.User{
		ID:       userID,
		Username: username,
		Email:    email,
		Name:     name,
		Phone:    phoneStr,
	}

	span.SetAttributes(attribute.Bool("profile.found", true))
	return user, nil
}

// CreateUser creates a new user profile
// Note: This assumes user_id already exists in auth.users (created via auth service)
// In production, user_id should be passed in request or extracted from auth context
func (s *UserService) CreateUser(ctx context.Context, req domain.CreateUserRequest) (*domain.User, error) {
	ctx, span := middleware.StartSpan(ctx, "user.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("username", req.Username),
		attribute.String("email", req.Email),
	))
	defer span.End()

	// Get database connection pool (pgx)
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Validate email format (basic validation)
	if !strings.Contains(req.Email, "@") {
		span.SetAttributes(attribute.Bool("user.created", false))
		return nil, fmt.Errorf("validate email %q for user %q: %w", req.Email, req.Username, ErrInvalidEmail)
	}

	// Parse name into first_name and last_name (simple split)
	nameParts := strings.Fields(req.Name)
	var firstName, lastName string
	if len(nameParts) > 0 {
		firstName = nameParts[0]
	}
	if len(nameParts) > 1 {
		lastName = strings.Join(nameParts[1:], " ")
	}

	// TODO: In production, user_id should come from auth service or be passed in request
	// For now, generate a mock user_id (in production, this should be the authenticated user's ID)
	// Check if profile already exists for this user_id
	// For demo purposes, use a hash of username as user_id
	userID := len(req.Username) + 100 // Simple mock user_id

	var existingID int
	checkQuery := `SELECT id FROM user_profiles WHERE user_id = $1`
	err := db.QueryRow(ctx, checkQuery, userID).Scan(&existingID)
	if err == nil {
		// Profile already exists
		span.SetAttributes(attribute.Bool("user.created", false))
		return nil, fmt.Errorf("create user %q: %w", req.Username, ErrUserExists)
	} else if !errors.Is(err, pgx.ErrNoRows) {
		// Database error
		span.RecordError(err)
		return nil, fmt.Errorf("check existing profile: %w", err)
	}

	// Insert new user profile
	insertQuery := `INSERT INTO user_profiles (user_id, first_name, last_name) VALUES ($1, $2, $3) RETURNING id`
	var profileID int
	err = db.QueryRow(ctx, insertQuery, userID, firstName, lastName).Scan(&profileID)
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
	span.AddEvent("user.created")

	return user, nil
}

// UpdateProfile updates the current user's profile
func (s *UserService) UpdateProfile(ctx context.Context, userID string, req domain.UpdateProfileRequest) (*domain.User, error) {
	ctx, span := middleware.StartSpan(ctx, "user.update_profile", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("user_id", userID),
	))
	defer span.End()

	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Parse user ID
	uid := 1
	if userID != "" {
		if parsed, err := strconv.Atoi(userID); err == nil {
			uid = parsed
		}
	}

	// Parse name into first_name and last_name
	nameParts := strings.Fields(req.Name)
	var firstName, lastName string
	if len(nameParts) > 0 {
		firstName = nameParts[0]
	}
	if len(nameParts) > 1 {
		lastName = strings.Join(nameParts[1:], " ")
	}

	// Update profile
	updateQuery := `UPDATE user_profiles SET first_name = $1, last_name = $2, phone = $3 WHERE user_id = $4`
	result, err := db.Exec(ctx, updateQuery, firstName, lastName, req.Phone, uid)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("update profile: %w", err)
	}

	if result.RowsAffected() == 0 {
		// Profile doesn't exist, create one
		insertQuery := `INSERT INTO user_profiles (user_id, first_name, last_name, phone) VALUES ($1, $2, $3, $4)`
		_, err = db.Exec(ctx, insertQuery, uid, firstName, lastName, req.Phone)
		if err != nil {
			span.RecordError(err)
			return nil, fmt.Errorf("create profile: %w", err)
		}
	}

	user := &domain.User{
		ID:   strconv.Itoa(uid),
		Name: req.Name,
	}

	span.SetAttributes(attribute.Bool("profile.updated", true))
	return user, nil
}