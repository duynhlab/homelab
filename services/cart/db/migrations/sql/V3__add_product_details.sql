-- V3__add_product_details.sql
-- Cart Database Schema Update
-- Last Updated: 2026-01-21
-- Purpose: Add product name and price columns to cart_items

-- =============================================================================
-- ADD PRODUCT DETAILS COLUMNS
-- =============================================================================
-- Store product name and price in cart_items for display purposes.

ALTER TABLE cart_items 
    ADD COLUMN IF NOT EXISTS product_name VARCHAR(255) NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS product_price DECIMAL(10,2) NOT NULL DEFAULT 0.00;

-- =============================================================================
-- UPDATE EXISTING DATA WITH PRODUCT INFO
-- =============================================================================
-- Based on seed data in V2__seed_cart.sql:
-- product_id 1 = Wireless Mouse ($29.99)
-- product_id 2 = Mechanical Keyboard ($79.99)
-- product_id 3 = USB-C Hub ($49.99)
-- product_id 4 = Laptop Stand ($89.99)
-- product_id 5 = Webcam HD ($69.99)

UPDATE cart_items SET product_name = 'Wireless Mouse', product_price = 29.99 WHERE product_id = 1;
UPDATE cart_items SET product_name = 'Mechanical Keyboard', product_price = 79.99 WHERE product_id = 2;
UPDATE cart_items SET product_name = 'USB-C Hub', product_price = 49.99 WHERE product_id = 3;
UPDATE cart_items SET product_name = 'Laptop Stand', product_price = 89.99 WHERE product_id = 4;
UPDATE cart_items SET product_name = 'Webcam HD', product_price = 69.99 WHERE product_id = 5;

-- =============================================================================
-- REMOVE DEFAULT CONSTRAINTS
-- =============================================================================
-- After populating data, remove defaults so new inserts require these values
ALTER TABLE cart_items 
    ALTER COLUMN product_name DROP DEFAULT,
    ALTER COLUMN product_price DROP DEFAULT;

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON COLUMN cart_items.product_name IS 'Product name at time of adding to cart';
COMMENT ON COLUMN cart_items.product_price IS 'Product price at time of adding to cart';

-- =============================================================================
-- VERIFICATION
-- =============================================================================
SELECT 
    'Product details added' as status,
    COUNT(*) as total_items,
    COUNT(CASE WHEN product_name != '' THEN 1 END) as items_with_name,
    COUNT(CASE WHEN product_price > 0 THEN 1 END) as items_with_price
FROM cart_items;
