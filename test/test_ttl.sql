/*
 * Test Suite for pg_ttl_index
 *
 * This file contains comprehensive tests for the TTL index extension.
 * Run with: make installcheck
 */

-- Basic extension installation test
CREATE EXTENSION IF NOT EXISTS pg_ttl_index;

-- Test 1: Create TTL index on a simple table
CREATE TABLE test_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    data TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Should succeed
SELECT ttl_create_index('test_sessions', 'created_at', 3600);

-- Verify configuration was created
SELECT table_name, column_name, expire_after_seconds, active
FROM ttl_index_table
WHERE table_name = 'test_sessions';

-- Test 2: Insert test data
INSERT INTO test_sessions (user_id, data, created_at) VALUES
    (1, 'session1', NOW() - INTERVAL '2 hours'),  -- Should be deleted
    (2, 'session2', NOW() - INTERVAL '30 minutes'), -- Should remain
    (3, 'session3', NOW());                         -- Should remain

-- Test 3: Run cleanup manually
SELECT ttl_runner();

-- Verify only the expired row was deleted
SELECT COUNT(*) as remaining_rows FROM test_sessions;

-- Test 4: Update TTL configuration
SELECT ttl_create_index('test_sessions', 'created_at', 7200);

-- Verify update
SELECT expire_after_seconds FROM ttl_index_table WHERE table_name = 'test_sessions';

-- Test 5: Test invalid column type (should fail)
CREATE TABLE test_invalid (
    id SERIAL PRIMARY KEY,
    created_at INTEGER  -- Invalid type
);

-- This should fail with an error
-- SELECT ttl_create_index('test_invalid', 'created_at', 3600);

-- Test 6: Test TTL summary function
SELECT * FROM ttl_summary();

-- Test 7: Drop TTL index
SELECT ttl_drop_index('test_sessions', 'created_at');

-- Verify it was removed
SELECT COUNT(*) FROM ttl_index_table WHERE table_name = 'test_sessions';

-- Cleanup
DROP TABLE test_sessions;
DROP TABLE test_invalid;

-- Test complete
SELECT 'All tests passed!' as result;
