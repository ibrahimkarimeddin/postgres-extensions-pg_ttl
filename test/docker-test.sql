/*
 * Docker Test Script for pg_ttl_index
 * 
 * This script tests the background worker functionality:
 * 1. Creates extension and starts worker
 * 2. Creates a test table with TTL
 * 3. Inserts expired data
 * 4. Monitors cleanup activity
 */

-- Create extension
CREATE EXTENSION IF NOT EXISTS pg_ttl_index;

-- Show current settings
SELECT name, setting FROM pg_settings WHERE name LIKE 'pg_ttl_index%';

-- Create test table
CREATE TABLE IF NOT EXISTS test_cleanup (
    id SERIAL PRIMARY KEY,
    message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Set up TTL of 15 seconds for testing
SELECT ttl_create_index('test_cleanup', 'created_at', 15);

-- Verify TTL configuration
SELECT * FROM ttl_index_table;

-- Insert test data - some expired, some fresh
INSERT INTO test_cleanup (message, created_at) VALUES
    ('expired_1', NOW() - INTERVAL '30 seconds'),
    ('expired_2', NOW() - INTERVAL '20 seconds'),
    ('fresh_1', NOW()),
    ('fresh_2', NOW() + INTERVAL '10 seconds');

-- Show current data
SELECT 'Before cleanup - Row count:' as status, COUNT(*) as count FROM test_cleanup;
SELECT id, message, created_at, 
       EXTRACT(EPOCH FROM (NOW() - created_at))::int as age_seconds
FROM test_cleanup ORDER BY created_at;

-- Start the background worker
SELECT ttl_start_worker();

-- Check worker status
SELECT 'Worker Status:' as info;
SELECT * FROM ttl_worker_status();

-- Note: Wait for naptime (10 seconds) then run this to check:
-- SELECT 'After cleanup - Row count:' as status, COUNT(*) as count FROM test_cleanup;
-- SELECT * FROM ttl_summary();
