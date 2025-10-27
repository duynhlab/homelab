package v2

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/demo/monitoring-golang/internal/review/domain"
)

func GetReview(c *gin.Context) {
	reviewId := c.Param("reviewId")
	review := domain.Review{
		ID:        reviewId,
		ProductID: "1",
		UserID:    "1",
		Rating:    5,
		Comment:   "Excellent product v2!",
	}
	c.JSON(http.StatusOK, review)
}

func CreateReview(c *gin.Context) {
	var req domain.CreateReviewRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	review := domain.Review{
		ID:        "new-review-v2",
		ProductID: req.ProductID,
		UserID:    req.UserID,
		Rating:    req.Rating,
		Comment:   req.Comment,
	}
	c.JSON(http.StatusCreated, review)
}