-- V1__init_schema.sql
-- Order Database Schema - Aligned with Phase 1 Repository
-- Last Updated: 2026-01-07
-- Phase: Production Baseline

-- =============================================================================
-- ORDERS TABLE
-- =============================================================================
-- Schema aligned with OrderRepository expectations:
--   SELECT id, user_id, status, subtotal, shipping, total, created_at
--
-- Critical changes from original V1:
--   - Renamed total_amount → total
--   - Added subtotal column
--   - Added shipping column
-- =============================================================================

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,  -- References auth.users.id (cross-service reference, no FK)
    subtotal DECIMAL(10, 2) NOT NULL CHECK (subtotal >= 0),
    shipping DECIMAL(10, 2) NOT NULL DEFAULT 5.00 CHECK (shipping >= 0),
    total DECIMAL(10, 2) NOT NULL CHECK (total >= 0),
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Business rule: total should equal subtotal + shipping
    CONSTRAINT check_order_total CHECK (total = subtotal + shipping)
);

-- =============================================================================
-- ORDER ITEMS TABLE
-- =============================================================================
-- Schema aligned with OrderRepository expectations:
--   SELECT product_id, product_name, quantity, price, subtotal
--   INSERT INTO order_items (order_id, product_id, product_name, quantity, price, subtotal)
--
-- Critical changes from original V1:
--   - Added product_name column (denormalized from products.name)
--   - Added subtotal column (quantity * price)
-- =============================================================================

CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL,  -- References product.products.id (cross-service reference, no FK)
    product_name VARCHAR(255) NOT NULL,  -- Denormalized from products table
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    price DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
    subtotal DECIMAL(10, 2) NOT NULL CHECK (subtotal >= 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Business rule: subtotal should equal quantity * price
    CONSTRAINT check_item_subtotal CHECK (subtotal = quantity * price)
);

-- =============================================================================
-- PERFORMANCE INDEXES
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id);

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE orders IS 'Customer orders with subtotal, shipping, and total breakdown';
COMMENT ON TABLE order_items IS 'Line items for each order with denormalized product data';

COMMENT ON COLUMN orders.user_id IS 'Cross-service reference to auth.users.id';
COMMENT ON COLUMN orders.subtotal IS 'Sum of all order items subtotals';
COMMENT ON COLUMN orders.shipping IS 'Shipping cost (currently fixed at $5.00)';
COMMENT ON COLUMN orders.total IS 'Subtotal + Shipping';

COMMENT ON COLUMN order_items.product_id IS 'Cross-service reference to product.products.id';
COMMENT ON COLUMN order_items.product_name IS 'Denormalized product name at time of order';
COMMENT ON COLUMN order_items.price IS 'Product price at time of order';
COMMENT ON COLUMN order_items.subtotal IS 'Quantity × Price';

COMMENT ON CONSTRAINT check_order_total ON orders IS 'Ensures total = subtotal + shipping';
COMMENT ON CONSTRAINT check_item_subtotal ON order_items IS 'Ensures subtotal = quantity × price';
