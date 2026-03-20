/*
 * Test Suite for pg_ttl_index v2.0
 *
 * This file contains comprehensive tests for the TTL index extension.
 * Run with: make installcheck
 */

-- Basic extension installation test
DROP EXTENSION IF EXISTS pg_ttl_index CASCADE;
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
SELECT schema_name, table_name, column_name, expire_after_seconds, batch_size, active,
       index_name IS NOT NULL as has_index, index_created_by_extension
FROM ttl_index_table
WHERE schema_name = 'public' AND table_name = 'test_sessions';

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
SELECT expire_after_seconds, batch_size, index_created_by_extension
FROM ttl_index_table
WHERE schema_name = 'public' AND table_name = 'test_sessions';

-- Test 5: Test TTL summary function with new fields
SELECT schema_name, table_name, column_name, expire_after_seconds, batch_size, active, index_name
FROM ttl_summary();

-- Test 6: Test stats tracking
SELECT schema_name, table_name, rows_deleted_last_run, total_rows_deleted FROM ttl_summary();

-- Test 7: Drop TTL index (should also drop the auto-created index)
SELECT ttl_drop_index('test_sessions', 'created_at');

-- Verify it was removed
SELECT COUNT(*) FROM ttl_index_table WHERE schema_name = 'public' AND table_name = 'test_sessions';

-- Verify index was dropped
SELECT COUNT(*) as index_count
FROM pg_indexes
WHERE tablename = 'test_sessions' AND indexname LIKE 'idx_ttl%';

-- Cleanup
DROP TABLE test_sessions;

-- Test 8: Pre-existing index should not be dropped
CREATE TABLE test_preexisting_index (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    payload TEXT
);

CREATE INDEX idx_preexisting_created_at ON test_preexisting_index(created_at);

SELECT ttl_create_index('test_preexisting_index', 'created_at', 3600);

-- Verify extension reuses pre-existing index and marks ownership correctly
SELECT index_name, index_created_by_extension
FROM ttl_index_table
WHERE schema_name = 'public' AND table_name = 'test_preexisting_index';

SELECT ttl_drop_index('test_preexisting_index', 'created_at');

-- Verify TTL config removed but pre-existing index still exists
SELECT COUNT(*) AS ttl_config_count
FROM ttl_index_table
WHERE schema_name = 'public' AND table_name = 'test_preexisting_index';

SELECT COUNT(*) AS preexisting_index_count
FROM pg_indexes
WHERE tablename = 'test_preexisting_index'
  AND indexname = 'idx_preexisting_created_at';

DROP TABLE test_preexisting_index;

-- Test 9: Schema-qualified names are tracked and executed correctly
CREATE SCHEMA ttl_schema_test_a;
CREATE SCHEMA ttl_schema_test_b;

CREATE TABLE ttl_schema_test_a.schema_sessions (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE ttl_schema_test_b.schema_sessions (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO ttl_schema_test_a.schema_sessions (created_at)
VALUES (NOW() - INTERVAL '2 hours');

INSERT INTO ttl_schema_test_b.schema_sessions (created_at)
VALUES (NOW() - INTERVAL '2 hours');

SELECT ttl_create_index('ttl_schema_test_a.schema_sessions', 'created_at', 3600);

SET search_path = ttl_schema_test_b, public;
SELECT ttl_runner();
RESET search_path;

SELECT COUNT(*) AS rows_left_a FROM ttl_schema_test_a.schema_sessions;
SELECT COUNT(*) AS rows_left_b FROM ttl_schema_test_b.schema_sessions;

SELECT schema_name, table_name
FROM ttl_index_table
WHERE table_name = 'schema_sessions'
ORDER BY schema_name;

SELECT ttl_drop_index('ttl_schema_test_a.schema_sessions', 'created_at');

DROP TABLE ttl_schema_test_a.schema_sessions;
DROP TABLE ttl_schema_test_b.schema_sessions;
DROP SCHEMA ttl_schema_test_a;
DROP SCHEMA ttl_schema_test_b;

-- Test 10: Soft delete mode should mark rows without hard delete
CREATE TABLE test_soft_delete (
    id SERIAL PRIMARY KEY,
    payload TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

SELECT ttl_create_index('test_soft_delete', 'created_at', 3600, 1000, 'deleted_at');

INSERT INTO test_soft_delete (payload, created_at) VALUES
    ('expired', NOW() - INTERVAL '2 hours'),
    ('fresh', NOW());

SELECT ttl_runner();

SELECT COUNT(*) AS soft_total_rows FROM test_soft_delete;
SELECT COUNT(*) AS soft_marked_rows FROM test_soft_delete WHERE deleted_at IS NOT NULL;
SELECT COUNT(*) AS soft_active_rows FROM test_soft_delete WHERE deleted_at IS NULL;

SELECT schema_name, table_name, soft_delete_column, cleanup_mode
FROM ttl_summary()
WHERE table_name = 'test_soft_delete';

SELECT ttl_drop_index('test_soft_delete', 'created_at');
DROP TABLE test_soft_delete;

-- Test complete
SELECT 'All tests passed!' as result;
