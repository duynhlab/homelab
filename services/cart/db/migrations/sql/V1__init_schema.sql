-- V1__init_schema.sql
-- Cart Database Schema - Aligned with Phase 1 Repository
-- Last Updated: 2026-01-07
-- Phase: Production Baseline

-- =============================================================================
-- CART ITEMS TABLE
-- =============================================================================
-- Note: This service has cross-service dependency on product.products table
-- for JOIN operations in CartRepository.FindByUserID():
--   SELECT ci.id, ci.product_id, p.name, p.price, ci.quantity
--   FROM cart_items ci
--   JOIN products p ON ci.product_id = p.id
--
-- This is acceptable for Phase 1 but should be refactored in future phases
-- by denormalizing product_name and product_price into cart_items.
-- =============================================================================

CREATE TABLE IF NOT EXISTS cart_items (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,  -- References auth.users.id (cross-service reference, no FK)
    product_id INTEGER NOT NULL,  -- References product.products.id (cross-service reference, no FK)
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_user_product UNIQUE(user_id, product_id)
);

-- =============================================================================
-- PERFORMANCE INDEXES
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_cart_items_user ON cart_items(user_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_product ON cart_items(product_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_updated_at ON cart_items(updated_at DESC);

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE cart_items IS 'Shopping cart items for each user';
COMMENT ON COLUMN cart_items.user_id IS 'Cross-service reference to auth.users.id';
COMMENT ON COLUMN cart_items.product_id IS 'Cross-service reference to product.products.id';
COMMENT ON CONSTRAINT unique_user_product ON cart_items IS 'Prevents duplicate products in same user cart';
