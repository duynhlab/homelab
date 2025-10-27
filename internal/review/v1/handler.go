package v1

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/demo/monitoring-golang/internal/review/domain"
)

func ListReviews(c *gin.Context) {
	reviews := []domain.Review{
		{ID: "1", ProductID: "1", UserID: "1", Rating: 5, Comment: "Great product!"},
		{ID: "2", ProductID: "2", UserID: "2", Rating: 4, Comment: "Good quality"},
	}
	c.JSON(http.StatusOK, reviews)
}

func CreateReview(c *gin.Context) {
	var req domain.CreateReviewRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	review := domain.Review{
		ID:        "new-review",
		ProductID: req.ProductID,
		UserID:    req.UserID,
		Rating:    req.Rating,
		Comment:   req.Comment,
	}
	c.JSON(http.StatusCreated, review)
}