/*
 * Test Suite for pg_ttl_index v2.0
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

-- Should succeed and create index automatically
SELECT ttl_create_index('test_sessions', 'created_at', 3600);

-- Verify index was created
SELECT COUNT(*) > 0 as index_created 
FROM pg_indexes 
WHERE tablename = 'test_sessions' AND indexname LIKE 'idx_ttl%';

-- Verify configuration was created with new fields
SELECT table_name, column_name, expire_after_seconds, batch_size, active, index_name IS NOT NULL as has_index
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

-- Test 4: Update TTL configuration with new batch_size
SELECT ttl_create_index('test_sessions', 'created_at', 7200, 5000);

-- Verify update
SELECT expire_after_seconds, batch_size FROM ttl_index_table WHERE table_name = 'test_sessions';

-- Test 5: Test TTL summary function with new fields
SELECT table_name, column_name, expire_after_seconds, batch_size, active, index_name 
FROM ttl_summary();

-- Test 6: Test stats tracking
SELECT table_name, rows_deleted_last_run, total_rows_deleted FROM ttl_summary();

-- Test 7: Drop TTL index (should also drop the auto-created index)
SELECT ttl_drop_index('test_sessions', 'created_at');

-- Verify it was removed
SELECT COUNT(*) FROM ttl_index_table WHERE table_name = 'test_sessions';

-- Verify index was dropped
SELECT COUNT(*) as index_count 
FROM pg_indexes 
WHERE tablename = 'test_sessions' AND indexname LIKE 'idx_ttl%';

-- Cleanup
DROP TABLE test_sessions;

-- Test complete
SELECT 'All tests passed!' as result;
