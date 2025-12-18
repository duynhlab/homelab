-- 001__init_schema.sql
-- Shipping-v2 Database Schema - Initial Setup

-- Shipment estimates table (for shipping cost estimates)
CREATE TABLE IF NOT EXISTS shipment_estimates (
    id SERIAL PRIMARY KEY,
    origin VARCHAR(255) NOT NULL,
    destination VARCHAR(255) NOT NULL,
    weight DECIMAL(10, 2) NOT NULL,
    cost DECIMAL(10, 2) NOT NULL,
    estimated_days INTEGER NOT NULL,
    carrier VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_shipment_estimates_origin ON shipment_estimates(origin);
CREATE INDEX IF NOT EXISTS idx_shipment_estimates_destination ON shipment_estimates(destination);
CREATE INDEX IF NOT EXISTS idx_shipment_estimates_created ON shipment_estimates(created_at);

-- Shipments table (for tracking shipments)
CREATE TABLE IF NOT EXISTS shipments (
    id SERIAL PRIMARY KEY,
    tracking_id VARCHAR(255) NOT NULL UNIQUE,
    order_id INTEGER,  -- References order.orders.id (cross-cluster, no FK)
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    origin VARCHAR(255),
    destination VARCHAR(255) NOT NULL,
    carrier VARCHAR(100),
    estimated_delivery TIMESTAMP,
    actual_delivery TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_shipments_tracking_id ON shipments(tracking_id);
CREATE INDEX IF NOT EXISTS idx_shipments_order_id ON shipments(order_id);
CREATE INDEX IF NOT EXISTS idx_shipments_status ON shipments(status);
CREATE INDEX IF NOT EXISTS idx_shipments_created ON shipments(created_at);

-- Shipment tracking history (for tracking status changes)
CREATE TABLE IF NOT EXISTS shipment_tracking_history (
    id SERIAL PRIMARY KEY,
    shipment_id INTEGER REFERENCES shipments(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL,
    location VARCHAR(255),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_tracking_history_shipment ON shipment_tracking_history(shipment_id);
CREATE INDEX IF NOT EXISTS idx_tracking_history_created ON shipment_tracking_history(created_at);

