-- =============================================================================
-- Auth Service - Seed Data
-- =============================================================================
-- Purpose: Demo users and sessions for local/dev/demo environments
-- Usage: Run after V1 migration to populate test users
-- Note: Password for all users is "password123" (bcrypt hashed)
-- =============================================================================

-- =============================================================================
-- DEMO USERS
-- =============================================================================
-- Password hash: bcrypt of "password123"
-- Generated with: bcrypt.GenerateFromPassword([]byte("password123"), bcrypt.DefaultCost)
INSERT INTO users (id, username, email, password_hash, created_at, last_login) VALUES
    (1, 'alice', 'alice@example.com', '$2a$10$J22gaM8P6seq9BEc9fRoye/6mc8aaCwm.KS27BmmWN5afiF.cGTrK', NOW() - INTERVAL '30 days', NOW() - INTERVAL '1 hour'),
    (2, 'bob', 'bob@example.com', '$2a$10$J22gaM8P6seq9BEc9fRoye/6mc8aaCwm.KS27BmmWN5afiF.cGTrK', NOW() - INTERVAL '25 days', NOW() - INTERVAL '2 hours'),
    (3, 'carol', 'carol@example.com', '$2a$10$J22gaM8P6seq9BEc9fRoye/6mc8aaCwm.KS27BmmWN5afiF.cGTrK', NOW() - INTERVAL '20 days', NOW() - INTERVAL '3 days'),
    (4, 'david', 'david@example.com', '$2a$10$J22gaM8P6seq9BEc9fRoye/6mc8aaCwm.KS27BmmWN5afiF.cGTrK', NOW() - INTERVAL '15 days', NOW() - INTERVAL '1 day'),
    (5, 'eve', 'eve@example.com', '$2a$10$J22gaM8P6seq9BEc9fRoye/6mc8aaCwm.KS27BmmWN5afiF.cGTrK', NOW() - INTERVAL '60 days', NOW() - INTERVAL '30 days')
ON CONFLICT (email) DO NOTHING;

-- =============================================================================
-- ACTIVE SESSIONS
-- =============================================================================
-- Active sessions for Alice and Bob (expires in 7 days)
INSERT INTO sessions (id, user_id, token, expires_at, created_at) VALUES
    (1, 1, 'demo_token_alice_12345', NOW() + INTERVAL '7 days', NOW() - INTERVAL '1 hour'),
    (2, 2, 'demo_token_bob_67890', NOW() + INTERVAL '7 days', NOW() - INTERVAL '2 hours')
ON CONFLICT (token) DO NOTHING;

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Verify seed data loaded
SELECT 
    'Auth seed data loaded' as status,
    (SELECT COUNT(*) FROM users) as user_count,
    (SELECT COUNT(*) FROM sessions) as session_count;
