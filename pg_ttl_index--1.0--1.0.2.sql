-- Upgrade script from version 1.0 to 1.0.2
--
-- This script handles the migration from pg_ttl_index 1.0 to 1.0.2
-- 
-- Changes in v1.0.2:
--   - Added helper functions: ttl_worker_status(), ttl_summary()
--   - Improved error handling in ttl_runner()
--   - Enhanced background worker stability

-- No schema changes from 1.0 to 1.0.2, only function updates
-- The ttl_index_table structure remains the same

-- Update ttl_runner function with improved error handling
CREATE OR REPLACE FUNCTION ttl_runner() RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
    delete_count INTEGER;
    total_deleted INTEGER := 0;
    delete_query TEXT;
    table_count INTEGER := 0;
    start_time TIMESTAMPTZ;
BEGIN
    start_time := NOW();
    
    -- Count active TTL configurations
    SELECT COUNT(*) INTO table_count 
    FROM ttl_index_table WHERE active = true;
    
    IF table_count = 0 THEN
        RETURN 0;
    END IF;
    
    FOR rec IN SELECT table_name, column_name, expire_after_seconds 
               FROM ttl_index_table WHERE active = true
               ORDER BY table_name, column_name
    LOOP
        BEGIN
            delete_query := format('DELETE FROM %I WHERE %I < NOW() - INTERVAL ''%s seconds''',
                                  rec.table_name, rec.column_name, rec.expire_after_seconds);
            
            EXECUTE delete_query;
            GET DIAGNOSTICS delete_count = ROW_COUNT;
            total_deleted := total_deleted + delete_count;
            
        EXCEPTION WHEN OTHERS THEN
            -- Log the error but continue with other tables
            RAISE WARNING 'TTL runner: Failed to cleanup table %.%: % (%)', 
                         rec.table_name, rec.column_name, SQLERRM, SQLSTATE;
        END;
    END LOOP;
    
    -- Update last run timestamp for all configurations
    UPDATE ttl_index_table SET last_run = start_time WHERE active = true;
    
    RETURN total_deleted;
END;
$$;

-- Add helper function to check worker status (new in 1.0.2)
CREATE OR REPLACE FUNCTION ttl_worker_status() 
RETURNS TABLE(
    worker_pid INTEGER,
    application_name TEXT,
    state TEXT,
    backend_start TIMESTAMPTZ,
    state_change TIMESTAMPTZ,
    query_start TIMESTAMPTZ,
    database_name TEXT
)
LANGUAGE sql
AS $$
    SELECT 
        pid::INTEGER as worker_pid,
        application_name::TEXT,
        state::TEXT,
        backend_start,
        state_change,
        query_start,
        datname::TEXT as database_name
    FROM pg_stat_activity 
    WHERE application_name LIKE 'TTL Worker DB %'
    ORDER BY backend_start DESC;
$$;

-- Add helper function to get TTL configuration summary (new in 1.0.2)
CREATE OR REPLACE FUNCTION ttl_summary()
RETURNS TABLE(
    table_name TEXT,
    column_name TEXT,
    expire_after_seconds INTEGER,
    active BOOLEAN,
    last_run TIMESTAMPTZ,
    time_since_last_run INTERVAL
)
LANGUAGE sql
AS $$
    SELECT 
        t.table_name,
        t.column_name,
        t.expire_after_seconds,
        t.active,
        t.last_run,
        CASE 
            WHEN t.last_run IS NOT NULL THEN NOW() - t.last_run
            ELSE NULL
        END as time_since_last_run
    FROM ttl_index_table t
    ORDER BY t.table_name, t.column_name;
$$;
