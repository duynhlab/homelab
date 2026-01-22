package v2

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	"github.com/jackc/pgx/v5"
	database "github.com/duynhne/monitoring/services/product/internal/core"
	"github.com/duynhne/monitoring/services/product/middleware"
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

	// Get database connection pool (pgx)
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Convert string ID to int
	productID, err := strconv.Atoi(itemId)
	if err != nil {
		span.SetAttributes(attribute.Bool("item.found", false))
		return nil, fmt.Errorf("invalid item id %q: %w", itemId, ErrProductNotFound)
	}

	// Query product - use pointers for nullable columns
	query := `
		SELECT p.id, p.name, p.description, p.price, COALESCE(c.name, 'Uncategorized') as category
		FROM products p
		LEFT JOIN categories c ON p.category_id = c.id
		WHERE p.id = $1
	`
	var name, description, category *string
	var price float64

	err = db.QueryRow(ctx, query, productID).Scan(&productID, &name, &description, &price, &category)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			span.SetAttributes(attribute.Bool("item.found", false))
			return nil, fmt.Errorf("get item by id %q: %w", itemId, ErrProductNotFound)
		}
		span.RecordError(err)
		return nil, fmt.Errorf("query item: %w", err)
	}

	item := &Item{
		ItemID:   strconv.Itoa(productID),
		Price:    price,
		SKU:      "SKU-" + strconv.Itoa(productID),
		Category: "Uncategorized",
	}
	if name != nil {
		item.Name = *name
	}
	if description != nil {
		item.Description = *description
	}
	if category != nil {
		item.Category = *category
	}

	span.SetAttributes(attribute.Bool("item.found", true))
	return item, nil
}

func (s *ProductService) CreateItem(ctx context.Context, req CreateItemRequest) (*Item, error) {
	ctx, span := middleware.StartSpan(ctx, "product.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("api.version", "v2"),
		attribute.String("item.name", req.Name),
	))
	defer span.End()

	// Get database connection pool (pgx)
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Validate price
	if req.Price <= 0 {
		span.SetAttributes(attribute.Bool("item.created", false))
		return nil, fmt.Errorf("validate price %.2f for item %q: %w", req.Price, req.Name, ErrInvalidPrice)
	}

	// Get or create category - use pointer for nullable category_id
	var categoryID *int
	if req.Category != "" {
		var catID int
		checkCatQuery := `SELECT id FROM categories WHERE name = $1`
		err := db.QueryRow(ctx, checkCatQuery, req.Category).Scan(&catID)
		if errors.Is(err, pgx.ErrNoRows) {
			createCatQuery := `INSERT INTO categories (name, description) VALUES ($1, $2) RETURNING id`
			err = db.QueryRow(ctx, createCatQuery, req.Category, "").Scan(&catID)
			if err != nil {
				span.RecordError(err)
				return nil, fmt.Errorf("create category: %w", err)
			}
		} else if err != nil {
			span.RecordError(err)
			return nil, fmt.Errorf("check category: %w", err)
		}
		categoryID = &catID
	}

	// Insert product
	insertQuery := `INSERT INTO products (name, description, price, category_id) VALUES ($1, $2, $3, $4) RETURNING id`
	var productID int
	err := db.QueryRow(ctx, insertQuery, req.Name, req.Description, req.Price, categoryID).Scan(&productID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("insert item: %w", err)
	}

	// Create inventory
	inventoryQuery := `INSERT INTO inventory (product_id, quantity) VALUES ($1, $2)`
	_, err = db.Exec(ctx, inventoryQuery, productID, 0)
	if err != nil {
		span.RecordError(fmt.Errorf("create inventory: %w", err))
	}

	item := &Item{
		ItemID:      strconv.Itoa(productID),
		Name:        req.Name,
		Price:       req.Price,
		Description: req.Description,
		Category:    req.Category,
		SKU:         req.SKU,
	}

	span.SetAttributes(
		attribute.String("item.id", item.ItemID),
		attribute.Bool("item.created", true),
	)
	span.AddEvent("item.created.v2")

	return item, nil
}
