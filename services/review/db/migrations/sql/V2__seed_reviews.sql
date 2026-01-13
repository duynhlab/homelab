-- =============================================================================
-- Review Service - Seed Data
-- =============================================================================
-- Purpose: Demo product reviews for local/dev/demo environments
-- Usage: Run after V1 migration to populate test reviews
-- Note: References auth.users (user_id) and product.products (product_id)
-- =============================================================================

-- =============================================================================
-- PRODUCT REVIEWS
-- =============================================================================
-- 12 reviews across 6 products (Wireless Mouse, Mechanical Keyboard, USB-C Hub, Webcam HD, Monitor, Gaming Headset)
-- Mix of ratings (3-5 stars) from different users

INSERT INTO reviews (id, product_id, user_id, rating, title, comment, created_at, updated_at) VALUES
    -- Wireless Mouse (product_id: 1) - 3 reviews
    (1, 1, 1, 5, 'Excellent mouse!', 'Very comfortable for long work sessions. Battery lasts forever!', NOW() - INTERVAL '15 days', NOW() - INTERVAL '15 days'),
    (2, 1, 3, 4, 'Good value', 'Works well but the scroll wheel is a bit stiff.', NOW() - INTERVAL '10 days', NOW() - INTERVAL '10 days'),
    (3, 1, 4, 5, 'Perfect for my setup', 'Connects instantly and tracks smoothly on any surface.', NOW() - INTERVAL '5 days', NOW() - INTERVAL '5 days'),
    
    -- Mechanical Keyboard (product_id: 2) - 2 reviews
    (4, 2, 3, 5, 'Best keyboard ever!', 'The Cherry MX switches feel amazing. RGB lighting is gorgeous!', NOW() - INTERVAL '12 days', NOW() - INTERVAL '12 days'),
    (5, 2, 5, 4, 'Great but loud', 'Love the tactile feedback but it is quite loud for an office.', NOW() - INTERVAL '18 days', NOW() - INTERVAL '18 days'),
    
    -- USB-C Hub (product_id: 3) - 2 reviews
    (6, 3, 1, 4, 'Very useful hub', 'All ports work perfectly. Gets a bit warm during heavy use.', NOW() - INTERVAL '8 days', NOW() - INTERVAL '8 days'),
    (7, 3, 4, 5, 'Essential for my laptop', 'Compact and reliable. HDMI output is crystal clear.', NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 days'),
    
    -- Webcam HD (product_id: 5) - 2 reviews
    (8, 5, 1, 5, 'Crystal clear video', 'Great for video calls. Auto-focus works perfectly!', NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days'),
    (9, 5, 3, 4, 'Good webcam', 'Image quality is good but microphone could be better.', NOW() - INTERVAL '7 days', NOW() - INTERVAL '7 days'),
    
    -- Monitor 24" (product_id: 6) - 2 reviews
    (10, 6, 4, 5, 'Beautiful display', 'Colors are vibrant and bezels are super thin. Love it!', NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 days'),
    (11, 6, 2, 4, 'Great monitor', 'Excellent for the price. Wish it had built-in speakers.', NOW() - INTERVAL '9 days', NOW() - INTERVAL '9 days'),
    
    -- Gaming Headset (product_id: 7) - 1 review
    (12, 7, 1, 5, 'Immersive sound!', 'Surround sound is incredible for gaming. Very comfortable too.', NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Verify seed data loaded
SELECT 
    'Reviews seeded' as status,
    COUNT(*) as review_count,
    COUNT(DISTINCT product_id) as products_reviewed,
    ROUND(AVG(rating), 2) as average_rating
FROM reviews;
