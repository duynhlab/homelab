package v1

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/demo/monitoring-golang/internal/auth/domain"
)

func Login(c *gin.Context) {
	var req domain.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Mock authentication
	if req.Username == "admin" && req.Password == "password" {
		user := domain.User{
			ID:       "1",
			Username: req.Username,
			Email:    "admin@example.com",
		}
		
		response := domain.AuthResponse{
			Token: "mock-jwt-token-v1",
			User:  user,
		}
		c.JSON(http.StatusOK, response)
	} else {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
	}
}

func Register(c *gin.Context) {
	var req domain.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Mock registration
	user := domain.User{
		ID:       "2",
		Username: req.Username,
		Email:    req.Email,
	}

	response := domain.AuthResponse{
		Token: "mock-jwt-token-v1",
		User:  user,
	}
	c.JSON(http.StatusCreated, response)
}