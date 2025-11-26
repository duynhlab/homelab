package v1

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/demo/monitoring-golang/internal/product/domain"
)

func ListProducts(c *gin.Context) {
	products := []domain.Product{
		{ID: "1", Name: "Product 1", Price: 100, Description: "Description 1", Category: "Electronics"},
		{ID: "2", Name: "Product 2", Price: 200, Description: "Description 2", Category: "Books"},
		{ID: "3", Name: "Product 3", Price: 150, Description: "Description 3", Category: "Clothing"},
	}
	c.JSON(http.StatusOK, products)
}

func GetProduct(c *gin.Context) {
	id := c.Param("id")
	product := domain.Product{
		ID:          id,
		Name:        "Product " + id,
		Price:       100,
		Description: "Description for product " + id,
		Category:    "Electronics",
	}
	c.JSON(http.StatusOK, product)
}

func CreateProduct(c *gin.Context) {
	var req domain.CreateProductRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	product := domain.Product{
		ID:          "new-" + req.Name,
		Name:        req.Name,
		Price:       req.Price,
		Description: req.Description,
		Category:    req.Category,
	}
	c.JSON(http.StatusCreated, product)
}
