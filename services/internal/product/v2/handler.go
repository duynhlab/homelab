package v2

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type Item struct {
	ItemID      string  `json:"itemId"`
	Name        string  `json:"name"`
	Price       float64 `json:"price"`
	Description string  `json:"description"`
	Category    string  `json:"category"`
	SKU         string  `json:"sku"`
}

type CreateItemRequest struct {
	Name        string  `json:"name" binding:"required"`
	Price       float64 `json:"price" binding:"required,min=0"`
	Description string  `json:"description"`
	Category    string  `json:"category"`
	SKU         string  `json:"sku"`
}

func ListItems(c *gin.Context) {
	items := []Item{
		{ItemID: "item-1", Name: "Item 1", Price: 100, Description: "Desc 1", Category: "Electronics", SKU: "SKU-001"},
		{ItemID: "item-2", Name: "Item 2", Price: 200, Description: "Desc 2", Category: "Books", SKU: "SKU-002"},
		{ItemID: "item-3", Name: "Item 3", Price: 150, Description: "Desc 3", Category: "Clothing", SKU: "SKU-003"},
	}
	c.JSON(http.StatusOK, items)
}

func GetItem(c *gin.Context) {
	itemId := c.Param("itemId")
	item := Item{
		ItemID:      itemId,
		Name:        "Item " + itemId,
		Price:       100,
		Description: "Description for item " + itemId,
		Category:    "Electronics",
		SKU:         "SKU-" + itemId,
	}
	c.JSON(http.StatusOK, item)
}

func CreateItem(c *gin.Context) {
	var req CreateItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	item := Item{
		ItemID:      "item-" + req.SKU,
		Name:        req.Name,
		Price:       req.Price,
		Description: req.Description,
		Category:    req.Category,
		SKU:         req.SKU,
	}
	c.JSON(http.StatusCreated, item)
}
