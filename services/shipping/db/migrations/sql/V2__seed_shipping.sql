-- =============================================================================
-- Shipping Service - Seed Data
-- =============================================================================
-- Purpose: Demo shipments for local/dev/demo environments
-- Usage: Run after V1 migration to populate test shipments
-- Note: References order.orders (order_id)
-- =============================================================================

-- =============================================================================
-- SHIPMENTS
-- =============================================================================
-- 3 shipments for completed/shipped orders
-- Carriers: USPS, FedEx, UPS
-- Statuses: in_transit, delivered, pending

INSERT INTO shipments (id, order_id, tracking_number, carrier, status, estimated_delivery, created_at, updated_at) VALUES
    -- Order 1 (Alice, completed) - Delivered
    (1, 1, '1Z999AA10123456784', 'UPS', 'delivered', NOW() - INTERVAL '8 days', NOW() - INTERVAL '10 days', NOW() - INTERVAL '8 days'),
    
    -- Order 2 (Alice, shipped) - In Transit
    (2, 2, '9400111899223344556677', 'USPS', 'in_transit', NOW() + INTERVAL '2 days', NOW() - INTERVAL '1 day', NOW() - INTERVAL '6 hours'),
    
    -- Order 4 (David, processing) - Pending
    (3, 4, '794612345678', 'FedEx', 'pending', NOW() + INTERVAL '5 days', NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 days')
ON CONFLICT (tracking_number) DO NOTHING;

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Verify seed data loaded
SELECT 
    'Shipments seeded' as status,
    COUNT(*) as shipment_count,
    COUNT(DISTINCT carrier) as carrier_count,
    COUNT(CASE WHEN status = 'in_transit' THEN 1 END) as in_transit_count
FROM shipments;
