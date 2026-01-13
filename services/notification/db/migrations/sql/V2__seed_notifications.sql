-- =============================================================================
-- Notification Service - Seed Data
-- =============================================================================
-- Purpose: Demo notifications for local/dev/demo environments
-- Usage: Run after V1 migration to populate test notifications
-- Note: References auth.users (user_id)
-- =============================================================================

-- =============================================================================
-- NOTIFICATIONS
-- =============================================================================
-- 8 notifications across 3 users (Alice, Bob, David)
-- Types: order_placed, order_shipped, review_reminder, promotion
-- Mix of read/unread status

INSERT INTO notifications (id, user_id, title, message, type, read, created_at) VALUES
    -- Alice's notifications (user_id: 1)
    (1, 1, 'Order Shipped', 'Your order #2 has been shipped and is on the way!', 'order_shipped', false, NOW() - INTERVAL '1 day'),
    (2, 1, 'Order Completed', 'Your order #1 has been delivered. Thank you for shopping!', 'order_completed', true, NOW() - INTERVAL '8 days'),
    (3, 1, 'Leave a Review', 'How was your Gaming Headset? Share your experience!', 'review_reminder', false, NOW() - INTERVAL '2 days'),
    
    -- Bob's notifications (user_id: 2)
    (4, 2, 'Special Promotion', 'Get 20% off on all monitors this weekend!', 'promotion', false, NOW() - INTERVAL '3 hours'),
    (5, 2, 'Cart Reminder', 'You have 2 items in your cart. Complete your purchase!', 'cart_reminder', false, NOW() - INTERVAL '1 day'),
    
    -- David's notifications (user_id: 4)
    (6, 4, 'Order Processing', 'Your order #4 is being processed and will ship soon.', 'order_processing', true, NOW() - INTERVAL '4 days'),
    (7, 4, 'Order Placed', 'Thank you! Your order #3 has been placed successfully.', 'order_placed', true, NOW() - INTERVAL '2 days'),
    (8, 4, 'New Arrivals', 'Check out our latest collection of gaming accessories!', 'promotion', false, NOW() - INTERVAL '6 hours')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Verify seed data loaded
SELECT 
    'Notifications seeded' as status,
    COUNT(*) as notification_count,
    COUNT(CASE WHEN read = false THEN 1 END) as unread_count,
    COUNT(DISTINCT user_id) as users_with_notifications
FROM notifications;
