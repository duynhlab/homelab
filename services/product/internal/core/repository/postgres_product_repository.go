package repository

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	"github.com/duynhne/monitoring/services/product/internal/core/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresProductRepository implements ProductRepository using PostgreSQL with pgx
type PostgresProductRepository struct {
	pool *pgxpool.Pool
}

// NewPostgresProductRepository creates a new PostgreSQL product repository
func NewPostgresProductRepository(pool *pgxpool.Pool) *PostgresProductRepository {
	return &PostgresProductRepository{pool: pool}
}

// FindByID retrieves a product by ID
func (r *PostgresProductRepository) FindByID(ctx context.Context, id string) (*domain.Product, error) {
	query := `
		SELECT p.id, p.name, p.description, p.price, COALESCE(c.name, 'Uncategorized') as category
		FROM products p
		LEFT JOIN categories c ON p.category_id = c.id
		WHERE p.id = $1
	`

	var product domain.Product
	var idInt int
	err := r.pool.QueryRow(ctx, query, id).Scan(
		&idInt, &product.Name, &product.Description, &product.Price, &product.Category,
	)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrNotFound
	}
	if err != nil {
		return nil, err
	}

	product.ID = strconv.Itoa(idInt)
	return &product, nil
}

// FindAll retrieves all products with optional filtering
func (r *PostgresProductRepository) FindAll(ctx context.Context, filters domain.ProductFilters) ([]domain.Product, error) {
	query := `
		SELECT p.id, p.name, p.description, p.price, COALESCE(c.name, 'Uncategorized') as category
		FROM products p
		LEFT JOIN categories c ON p.category_id = c.id
		WHERE 1=1
	`

	args := []interface{}{}
	argPos := 1

	if filters.Category != "" {
		query += fmt.Sprintf(" AND c.name = $%d", argPos)
		args = append(args, filters.Category)
		argPos++
	}

	if filters.Search != "" {
		query += fmt.Sprintf(" AND p.name ILIKE $%d", argPos)
		args = append(args, "%"+filters.Search+"%")
		argPos++
	}

	sortBy := filters.SortBy
	allowedSortFields := map[string]string{
		"id": "p.id", "name": "p.name", "price": "p.price", "created_at": "p.created_at",
	}
	
	sortColumn := allowedSortFields["created_at"]
	if sortBy != "" {
		if col, ok := allowedSortFields[sortBy]; ok {
			sortColumn = col
		}
	}
	
	order := filters.Order
	if order != "ASC" && order != "DESC" {
		order = "DESC"
	}
	query += fmt.Sprintf(" ORDER BY %s %s", sortColumn, order)

	limit := filters.Limit
	if limit == 0 {
		limit = 20
	}
	offset := (filters.Page - 1) * limit
	if offset < 0 {
		offset = 0
	}
	query += fmt.Sprintf(" LIMIT $%d OFFSET $%d", argPos, argPos+1)
	args = append(args, limit, offset)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var products []domain.Product
	for rows.Next() {
		var product domain.Product
		var idInt int
		err := rows.Scan(&idInt, &product.Name, &product.Description, &product.Price, &product.Category)
		if err != nil {
			continue
		}
		product.ID = strconv.Itoa(idInt)
		products = append(products, product)
	}

	return products, nil
}

// FindRelatedProducts finds products in the same category
func (r *PostgresProductRepository) FindRelatedProducts(ctx context.Context, productID string, limit int) ([]domain.Product, error) {
	query := `
		SELECT p2.id, p2.name, p2.price
		FROM products p1
		JOIN products p2 ON p1.category_id = p2.category_id
		WHERE p1.id = $1 AND p2.id != $1
		LIMIT $2
	`

	rows, err := r.pool.Query(ctx, query, productID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var products []domain.Product
	for rows.Next() {
		var product domain.Product
		var idInt int
		err := rows.Scan(&idInt, &product.Name, &product.Price)
		if err != nil {
			continue
		}
		product.ID = strconv.Itoa(idInt)
		products = append(products, product)
	}

	return products, nil
}

// Create creates a new product
func (r *PostgresProductRepository) Create(ctx context.Context, product *domain.Product) error {
	query := `
		INSERT INTO products (name, description, price, category_id)
		VALUES ($1, $2, $3, (SELECT id FROM categories WHERE name = $4))
		RETURNING id
	`

	var id int
	err := r.pool.QueryRow(ctx, query, product.Name, product.Description, product.Price, product.Category).Scan(&id)
	if err != nil {
		return err
	}

	product.ID = strconv.Itoa(id)
	return nil
}

// Update updates an existing product
func (r *PostgresProductRepository) Update(ctx context.Context, product *domain.Product) error {
	query := `
		UPDATE products
		SET name = $1, description = $2, price = $3,
		    category_id = (SELECT id FROM categories WHERE name = $4)
		WHERE id = $5
	`

	result, err := r.pool.Exec(ctx, query, product.Name, product.Description, product.Price, product.Category, product.ID)
	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}

// Delete deletes a product
func (r *PostgresProductRepository) Delete(ctx context.Context, id string) error {
	query := `DELETE FROM products WHERE id = $1`

	result, err := r.pool.Exec(ctx, query, id)
	if err != nil {
		return err
	}

	if result.RowsAffected() == 0 {
		return domain.ErrNotFound
	}

	return nil
}
