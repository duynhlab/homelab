-- =============================================================================
-- Product Service - Seed Data
-- =============================================================================
-- Purpose: Initial product catalog for production deployment
-- Usage: Run after V1 migration to populate initial product inventory
-- Note: This provides the baseline product catalog for the e-commerce store
-- =============================================================================

-- =============================================================================
-- INITIAL PRODUCT CATALOG
-- =============================================================================
INSERT INTO products (name, description, price, category_id, stock_quantity) VALUES
    ('Wireless Mouse', 'Ergonomic wireless mouse with long battery life', 29.99, 1, 50),
    ('Mechanical Keyboard', 'RGB mechanical gaming keyboard with Cherry MX switches', 79.99, 4, 30),
    ('USB-C Hub', '7-in-1 USB-C hub with HDMI, USB 3.0, and SD card readers', 39.99, 2, 25),
    ('Laptop Stand', 'Adjustable aluminum laptop stand for better ergonomics', 44.99, 3, 40),
    ('Webcam HD', '1080p HD webcam with built-in microphone', 59.99, 1, 20),
    ('Monitor 24"', '24-inch Full HD IPS monitor with ultra-thin bezels', 149.99, 1, 15),
    ('Gaming Headset', 'Surround sound gaming headset with noise cancellation', 89.99, 3, 35),
    ('External SSD 1TB', 'Portable 1TB SSD with USB 3.1 Gen 2 interface', 99.99, 2, 18),
    ('Bluetooth Speaker', 'Portable Bluetooth speaker with deep bass and 12-hour playtime', 34.99, 3, 28),
    ('Smartphone Stand', 'Adjustable smartphone stand compatible with all devices', 19.99, 3, 60),
    ('USB Flash Drive 128GB', 'High-speed USB 3.0 flash drive with 128GB capacity', 22.99, 2, 75),
    ('4K HDMI Cable', '2-meter ultra HD 4K HDMI cable with gold-plated connectors', 12.99, 2, 120),
    ('Noise Cancelling Earbuds', 'True wireless earbuds with active noise cancellation', 59.99, 3, 38)
ON CONFLICT (name) DO NOTHING;

-- Verify seed data loaded
SELECT 
    'Initial product catalog loaded' as status,
    COUNT(*) as product_count,
    SUM(stock_quantity) as total_stock
FROM products;