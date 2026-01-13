package v1

import (
	"context"
	"database/sql"
	"fmt"
	"strconv"
	"time"

	"github.com/duynhne/monitoring/services/auth/internal/core"
	"github.com/duynhne/monitoring/services/auth/internal/core/domain"
	"github.com/duynhne/monitoring/services/auth/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"golang.org/x/crypto/bcrypt"
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

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Query user from database
	var userID int
	var username, email, passwordHash string
	var lastLogin sql.NullTime

	query := `SELECT id, username, email, password_hash, last_login FROM users WHERE username = $1`
	err := db.QueryRowContext(ctx, query, req.Username).Scan(&userID, &username, &email, &passwordHash, &lastLogin)
	if err != nil {
		if err == sql.ErrNoRows {
			span.SetAttributes(attribute.Bool("auth.success", false))
			span.AddEvent("authentication.failed")
			return nil, fmt.Errorf("authenticate user %q: %w", req.Username, ErrUserNotFound)
		}
		span.RecordError(err)
		return nil, fmt.Errorf("query user %q: %w", req.Username, err)
	}

	// Verify password
	err = bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password))
	if err != nil {
		span.SetAttributes(attribute.Bool("auth.success", false))
		span.AddEvent("authentication.failed")
		return nil, fmt.Errorf("authenticate user %q: %w", req.Username, ErrInvalidCredentials)
	}

	// Update last_login timestamp
	updateQuery := `UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = $1`
	_, err = db.ExecContext(ctx, updateQuery, userID)
	if err != nil {
		// Log error but don't fail login
		span.RecordError(fmt.Errorf("update last_login: %w", err))
	}

	// Create session token (simplified - in production use JWT)
	token := fmt.Sprintf("jwt-token-v1-%d-%d", userID, time.Now().Unix())

	// Insert session into database
	sessionQuery := `INSERT INTO sessions (user_id, token, expires_at) VALUES ($1, $2, $3)`
	expiresAt := time.Now().Add(24 * time.Hour) // 24 hour expiry
	_, err = db.ExecContext(ctx, sessionQuery, userID, token, expiresAt)
	if err != nil {
		// Log error but don't fail login
		span.RecordError(fmt.Errorf("create session: %w", err))
	}

	user := domain.User{
		ID:       strconv.Itoa(userID),
		Username: username,
		Email:    email,
	}

	response := &domain.AuthResponse{
		Token: token,
		User:  user,
	}

	span.SetAttributes(
		attribute.String("user.id", user.ID),
		attribute.Bool("auth.success", true),
	)
	span.AddEvent("user.authenticated")

	return response, nil
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

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Hash password
	passwordHash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("hash password: %w", err)
	}

	// Check if username or email already exists
	var existingID int
	checkQuery := `SELECT id FROM users WHERE username = $1 OR email = $2`
	err = db.QueryRowContext(ctx, checkQuery, req.Username, req.Email).Scan(&existingID)
	if err == nil {
		// User already exists
		span.SetAttributes(attribute.Bool("registration.success", false))
		return nil, fmt.Errorf("register user %q: %w", req.Username, ErrUserExists)
	} else if err != sql.ErrNoRows {
		// Database error
		span.RecordError(err)
		return nil, fmt.Errorf("check existing user: %w", err)
	}

	// Insert new user
	insertQuery := `INSERT INTO users (username, email, password_hash) VALUES ($1, $2, $3) RETURNING id`
	var userID int
	err = db.QueryRowContext(ctx, insertQuery, req.Username, req.Email, string(passwordHash)).Scan(&userID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("insert user: %w", err)
	}

	// Create session token
	token := fmt.Sprintf("jwt-token-v1-%d-%d", userID, time.Now().Unix())

	// Insert session
	sessionQuery := `INSERT INTO sessions (user_id, token, expires_at) VALUES ($1, $2, $3)`
	expiresAt := time.Now().Add(24 * time.Hour)
	_, err = db.ExecContext(ctx, sessionQuery, userID, token, expiresAt)
	if err != nil {
		// Log error but don't fail registration
		span.RecordError(fmt.Errorf("create session: %w", err))
	}

	user := domain.User{
		ID:       strconv.Itoa(userID),
		Username: req.Username,
		Email:    req.Email,
	}

	response := &domain.AuthResponse{
		Token: token,
		User:  user,
	}

	span.SetAttributes(
		attribute.String("user.id", user.ID),
		attribute.Bool("registration.success", true),
	)
	span.AddEvent("user.registered")

	return response, nil
}
