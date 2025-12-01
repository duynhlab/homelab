package v2

import (
	"context"

	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
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

type ProductService struct{}

func NewProductService() *ProductService {
	return &ProductService{}
}

func (s *ProductService) ListItems(ctx context.Context) ([]Item, error) {
	ctx, span := middleware.StartSpan(ctx, "product.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
	))
	defer span.End()

	items := []Item{
		{ItemID: "item-1", Name: "Item 1", Price: 100, Description: "Desc 1", Category: "Electronics", SKU: "SKU-001"},
		{ItemID: "item-2", Name: "Item 2", Price: 200, Description: "Desc 2", Category: "Books", SKU: "SKU-002"},
		{ItemID: "item-3", Name: "Item 3", Price: 150, Description: "Desc 3", Category: "Clothing", SKU: "SKU-003"},
	}
	return items, nil
}

func (s *ProductService) GetItem(ctx context.Context, itemId string) (*Item, error) {
	ctx, span := middleware.StartSpan(ctx, "product.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("item.id", itemId),
	))
	defer span.End()

	item := &Item{
		ItemID:      itemId,
		Name:        "Item " + itemId,
		Price:       100,
		Description: "Description for item " + itemId,
		Category:    "Electronics",
		SKU:         "SKU-" + itemId,
	}
	return item, nil
}

func (s *ProductService) CreateItem(ctx context.Context, req CreateItemRequest) (*Item, error) {
	ctx, span := middleware.StartSpan(ctx, "product.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("item.name", req.Name),
	))
	defer span.End()

	item := &Item{
		ItemID:      "item-" + req.SKU,
		Name:        req.Name,
		Price:       req.Price,
		Description: req.Description,
		Category:    req.Category,
		SKU:         req.SKU,
	}
	span.SetAttributes(attribute.String("item.id", item.ItemID))
	return item, nil
}

