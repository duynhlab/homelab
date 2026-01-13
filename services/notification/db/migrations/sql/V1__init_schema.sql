-- V1__init_schema.sql
-- Notification Database Schema - Initial Setup

-- Notifications table
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,  -- References auth.users.id (cross-cluster, no FK)
    title VARCHAR(255) NOT NULL,
    message TEXT,
    type VARCHAR(50),
    read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);

