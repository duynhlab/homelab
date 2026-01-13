-- =============================================================================
-- User Service - Seed Data
-- =============================================================================
-- Purpose: Demo user profiles for local/dev/demo environments
-- Usage: Run after V1 migration to populate test user profiles
-- Note: References auth.users (user_id: 1-5, cross-service reference)
-- =============================================================================

-- =============================================================================
-- USER PROFILES
-- =============================================================================
INSERT INTO user_profiles (id, user_id, first_name, last_name, phone, address, created_at, updated_at) VALUES
    (1, 1, 'Alice', 'Johnson', '+1-555-0101', '123 Main St, San Francisco, CA 94102', NOW() - INTERVAL '30 days', NOW() - INTERVAL '5 days'),
    (2, 2, 'Bob', 'Smith', '+1-555-0102', '456 Oak Ave, Seattle, WA 98101', NOW() - INTERVAL '25 days', NOW() - INTERVAL '10 days'),
    (3, 3, 'Carol', 'White', '+1-555-0103', '789 Pine Rd, Portland, OR 97201', NOW() - INTERVAL '20 days', NOW() - INTERVAL '2 days'),
    (4, 4, 'David', 'Brown', '+1-555-0104', '321 Elm St, Austin, TX 78701', NOW() - INTERVAL '15 days', NOW() - INTERVAL '1 day'),
    (5, 5, 'Eve', 'Davis', '+1-555-0105', '654 Maple Dr, Boston, MA 02101', NOW() - INTERVAL '60 days', NOW() - INTERVAL '60 days')
ON CONFLICT (user_id) DO NOTHING;

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Verify seed data loaded
SELECT 
    'User profiles seeded' as status,
    COUNT(*) as profile_count
FROM user_profiles;
