-- V1__init_schema.sql
-- Shipping Database Schema - Initial Setup

-- Shipments table
CREATE TABLE IF NOT EXISTS shipments (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL,  -- References order.orders.id (cross-cluster, no FK)
    tracking_number VARCHAR(100) NOT NULL UNIQUE,
    carrier VARCHAR(50),
    status VARCHAR(50) DEFAULT 'pending',
    estimated_delivery TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_shipments_order ON shipments(order_id);
CREATE INDEX IF NOT EXISTS idx_shipments_tracking ON shipments(tracking_number);
CREATE INDEX IF NOT EXISTS idx_shipments_status ON shipments(status);

