package v1

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/demo/monitoring-golang/internal/user/domain"
)

func GetUser(c *gin.Context) {
	id := c.Param("id")
	user := domain.User{
		ID:       id,
		Username: "user" + id,
		Email:    "user" + id + "@example.com",
		Name:     "User " + id,
	}
	c.JSON(http.StatusOK, user)
}

func GetProfile(c *gin.Context) {
	user := domain.User{
		ID:       "1",
		Username: "current_user",
		Email:    "current@example.com",
		Name:     "Current User",
	}
	c.JSON(http.StatusOK, user)
}

func CreateUser(c *gin.Context) {
	var req domain.CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := domain.User{
		ID:       "new-" + req.Username,
		Username: req.Username,
		Email:    req.Email,
		Name:     req.Name,
	}
	c.JSON(http.StatusCreated, user)
}
