-- =============================================================================
-- Cart Service - Seed Data
-- =============================================================================
-- Purpose: Demo cart items for local/dev/demo environments
-- Usage: Run after V1 migration to populate test cart items
-- Note: References auth.users (user_id) and product.products (product_id)
-- =============================================================================

-- =============================================================================
-- CART ITEMS
-- =============================================================================
-- Alice's cart: 3 items (Wireless Mouse x2, Mechanical Keyboard x1, Webcam HD x1)
-- Bob's cart: 2 items (USB-C Hub x1, Laptop Stand x1)
-- Carol, David, Eve: No cart items (empty carts)

INSERT INTO cart_items (id, user_id, product_id, product_name, product_price, quantity, created_at, updated_at) VALUES
    -- Alice's cart (user_id: 1)
    (1, 1, 1, 'Wireless Mouse', 29.99, 2, NOW() - INTERVAL '3 days', NOW() - INTERVAL '1 day'),   -- Wireless Mouse x2
    (2, 1, 2, 'Mechanical Keyboard', 79.99, 1, NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days'),  -- Mechanical Keyboard x1
    (3, 1, 5, 'Webcam HD', 69.99, 1, NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day'),    -- Webcam HD x1
    
    -- Bob's cart (user_id: 2)
    (4, 2, 3, 'USB-C Hub', 49.99, 1, NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days'),  -- USB-C Hub x1
    (5, 2, 4, 'Laptop Stand', 89.99, 1, NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days')   -- Laptop Stand x1
ON CONFLICT (user_id, product_id) DO NOTHING;

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Verify seed data loaded
SELECT 
    'Cart items seeded' as status,
    COUNT(*) as cart_item_count,
    COUNT(DISTINCT user_id) as users_with_carts
FROM cart_items;
