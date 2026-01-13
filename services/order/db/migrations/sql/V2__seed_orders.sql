-- =============================================================================
-- Order Service - Seed Data
-- =============================================================================
-- Purpose: Demo orders and order items for local/dev/demo environments
-- Usage: Run after V1 migration to populate test orders
-- Note: References auth.users (user_id) and product.products (product_id)
-- =============================================================================

-- =============================================================================
-- ORDERS
-- =============================================================================
-- Alice: 2 orders (1 completed, 1 shipped)
-- David: 2 orders (1 pending, 1 processing)
-- Eve: 1 order (completed)

INSERT INTO orders (id, user_id, subtotal, shipping, total, status, created_at, updated_at) VALUES
    -- Alice's orders
    (1, 1, 109.97, 5.00, 114.97, 'completed', NOW() - INTERVAL '10 days', NOW() - INTERVAL '8 days'),
    (2, 1, 169.97, 5.00, 174.97, 'shipped', NOW() - INTERVAL '3 days', NOW() - INTERVAL '1 day'),
    
    -- David's orders
    (3, 4, 59.98, 5.00, 64.98, 'pending', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days'),
    (4, 4, 149.99, 5.00, 154.99, 'processing', NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days'),
    
    -- Eve's order
    (5, 5, 79.99, 5.00, 84.99, 'completed', NOW() - INTERVAL '20 days', NOW() - INTERVAL '18 days')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- ORDER ITEMS
-- =============================================================================
INSERT INTO order_items (id, order_id, product_id, product_name, quantity, price, subtotal, created_at) VALUES
    -- Order 1 (Alice, completed): Wireless Mouse x2, USB-C Hub x1, Laptop Stand x1
    (1, 1, 1, 'Wireless Mouse', 2, 29.99, 59.98, NOW() - INTERVAL '10 days'),
    (2, 1, 3, 'USB-C Hub', 1, 39.99, 39.99, NOW() - INTERVAL '10 days'),
    (3, 1, 4, 'Laptop Stand', 1, 44.99, 44.99, NOW() - INTERVAL '10 days'),
    
    -- Order 2 (Alice, shipped): Webcam HD x1, Gaming Headset x1
    (4, 2, 5, 'Webcam HD', 1, 59.99, 59.99, NOW() - INTERVAL '3 days'),
    (5, 2, 7, 'Gaming Headset', 1, 89.99, 89.99, NOW() - INTERVAL '3 days'),
    
    -- Order 3 (David, pending): Wireless Mouse x2
    (6, 3, 1, 'Wireless Mouse', 2, 29.99, 59.98, NOW() - INTERVAL '2 days'),
    
    -- Order 4 (David, processing): Monitor 24" x1
    (7, 4, 6, 'Monitor 24"', 1, 149.99, 149.99, NOW() - INTERVAL '5 days'),
    
    -- Order 5 (Eve, completed): Mechanical Keyboard x1
    (8, 5, 2, 'Mechanical Keyboard', 1, 79.99, 79.99, NOW() - INTERVAL '20 days')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Verify seed data loaded
SELECT 
    'Orders seeded' as status,
    (SELECT COUNT(*) FROM orders) as order_count,
    (SELECT COUNT(*) FROM order_items) as order_item_count,
    (SELECT SUM(total) FROM orders) as total_revenue
FROM orders
LIMIT 1;
