package v1

import (
	"context"
	"database/sql"
	"fmt"
	"strconv"

	database "github.com/duynhne/monitoring/internal/product/core"
	"github.com/duynhne/monitoring/internal/product/core/domain"
	"github.com/duynhne/monitoring/pkg/middleware"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type ProductService struct{}

func NewProductService() *ProductService {
	return &ProductService{}
}

func (s *ProductService) ListProducts(ctx context.Context) ([]domain.Product, error) {
	ctx, span := middleware.StartSpan(ctx, "product.list", trace.WithAttributes(
		attribute.String("layer", "logic"),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Query products with category join
	query := `
		SELECT p.id, p.name, p.description, p.price, COALESCE(c.name, 'Uncategorized') as category
		FROM products p
		LEFT JOIN categories c ON p.category_id = c.id
		ORDER BY p.created_at DESC
	`
	rows, err := db.QueryContext(ctx, query)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("query products: %w", err)
	}
	defer rows.Close()

	var products []domain.Product
	for rows.Next() {
		var product domain.Product
		var category sql.NullString
		var price float64
		var id int

		err := rows.Scan(&id, &product.Name, &product.Description, &price, &category)
		if err != nil {
			span.RecordError(err)
			continue
		}

		// Convert ID to string
		product.ID = strconv.Itoa(id)
		product.Price = price
		if category.Valid {
			product.Category = category.String
		} else {
			product.Category = "Uncategorized"
		}

		products = append(products, product)
	}

	if err = rows.Err(); err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("scan products: %w", err)
	}

	span.SetAttributes(attribute.Int("products.count", len(products)))
	return products, nil
}

func (s *ProductService) GetProduct(ctx context.Context, id string) (*domain.Product, error) {
	ctx, span := middleware.StartSpan(ctx, "product.get", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.id", id),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Convert string ID to int
	productID, err := strconv.Atoi(id)
	if err != nil {
		span.SetAttributes(attribute.Bool("product.found", false))
		return nil, fmt.Errorf("invalid product id %q: %w", id, ErrProductNotFound)
	}

	// Query product with category
	query := `
		SELECT p.id, p.name, p.description, p.price, COALESCE(c.name, 'Uncategorized') as category
		FROM products p
		LEFT JOIN categories c ON p.category_id = c.id
		WHERE p.id = $1
	`
	var name, description sql.NullString
	var price float64
	var category sql.NullString

	err = db.QueryRowContext(ctx, query, productID).Scan(&productID, &name, &description, &price, &category)
	if err != nil {
		if err == sql.ErrNoRows {
			span.SetAttributes(attribute.Bool("product.found", false))
			return nil, fmt.Errorf("get product by id %q: %w", id, ErrProductNotFound)
		}
		span.RecordError(err)
		return nil, fmt.Errorf("query product: %w", err)
	}

	product := &domain.Product{
		ID:    strconv.Itoa(productID),
		Price: price,
	}
	if name.Valid {
		product.Name = name.String
	}
	if description.Valid {
		product.Description = description.String
	}
	if category.Valid {
		product.Category = category.String
	} else {
		product.Category = "Uncategorized"
	}

	span.SetAttributes(attribute.Bool("product.found", true))
	return product, nil
}

func (s *ProductService) CreateProduct(ctx context.Context, req domain.CreateProductRequest) (*domain.Product, error) {
	ctx, span := middleware.StartSpan(ctx, "product.create", trace.WithAttributes(
		attribute.String("layer", "logic"),
		attribute.String("product.name", req.Name),
	))
	defer span.End()

	// Get database connection
	db := database.GetDB()
	if db == nil {
		return nil, fmt.Errorf("database connection not available")
	}

	// Validate price
	if req.Price <= 0 {
		span.SetAttributes(attribute.Bool("product.created", false))
		return nil, fmt.Errorf("validate price %.2f for product %q: %w", req.Price, req.Name, ErrInvalidPrice)
	}

	// Get or create category
	var categoryID sql.NullInt64
	if req.Category != "" {
		// Check if category exists
		var catID int
		checkCatQuery := `SELECT id FROM categories WHERE name = $1`
		err := db.QueryRowContext(ctx, checkCatQuery, req.Category).Scan(&catID)
		if err == sql.ErrNoRows {
			// Create category
			createCatQuery := `INSERT INTO categories (name, description) VALUES ($1, $2) RETURNING id`
			err = db.QueryRowContext(ctx, createCatQuery, req.Category, "").Scan(&catID)
			if err != nil {
				span.RecordError(err)
				return nil, fmt.Errorf("create category: %w", err)
			}
		} else if err != nil {
			span.RecordError(err)
			return nil, fmt.Errorf("check category: %w", err)
		}
		categoryID = sql.NullInt64{Int64: int64(catID), Valid: true}
	}

	// Insert product
	insertQuery := `INSERT INTO products (name, description, price, category_id) VALUES ($1, $2, $3, $4) RETURNING id`
	var productID int
	err := db.QueryRowContext(ctx, insertQuery, req.Name, req.Description, req.Price, categoryID).Scan(&productID)
	if err != nil {
		span.RecordError(err)
		return nil, fmt.Errorf("insert product: %w", err)
	}

	// Create inventory entry
	inventoryQuery := `INSERT INTO inventory (product_id, quantity) VALUES ($1, $2)`
	_, err = db.ExecContext(ctx, inventoryQuery, productID, 0)
	if err != nil {
		// Log but don't fail (inventory can be created later)
		span.RecordError(fmt.Errorf("create inventory: %w", err))
	}

	product := &domain.Product{
		ID:          strconv.Itoa(productID),
		Name:        req.Name,
		Price:       req.Price,
		Description: req.Description,
		Category:    req.Category,
	}

	span.SetAttributes(
		attribute.String("product.id", product.ID),
		attribute.Bool("product.created", true),
	)
	span.AddEvent("product.created")

	return product, nil
}
