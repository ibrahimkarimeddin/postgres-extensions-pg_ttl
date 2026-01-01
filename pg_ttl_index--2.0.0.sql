CREATE TABLE ttl_index_table (
    table_name TEXT NOT NULL,
    column_name TEXT NOT NULL,
    expire_after_seconds INTEGER NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_run TIMESTAMPTZ,
    -- High-load optimizations
    batch_size INTEGER NOT NULL DEFAULT 10000,
    rows_deleted_last_run BIGINT DEFAULT 0,
    total_rows_deleted BIGINT DEFAULT 0,
    index_name TEXT,
    PRIMARY KEY (table_name, column_name)
);

-- Create TTL index with auto-indexing
CREATE FUNCTION ttl_create_index(
    p_table_name TEXT,
    p_column_name TEXT,
    p_expire_after_seconds INTEGER,
    p_batch_size INTEGER DEFAULT 10000
) RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_idx_name TEXT;
BEGIN
    -- Create index name
    v_idx_name := 'idx_ttl_' || p_table_name || '_' || p_column_name;
    
    -- Create index on timestamp column for fast deletes
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (%I)', 
                   v_idx_name, p_table_name, p_column_name);
    
    -- Insert or update TTL configuration
    INSERT INTO ttl_index_table (table_name, column_name, expire_after_seconds, batch_size, index_name, active, created_at) 
    VALUES (p_table_name, p_column_name, p_expire_after_seconds, p_batch_size, v_idx_name, true, NOW()) 
    ON CONFLICT (table_name, column_name) DO UPDATE SET 
        expire_after_seconds = p_expire_after_seconds,
        batch_size = p_batch_size,
        active = true,
        updated_at = NOW();
    
    RETURN true;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'TTL create_index failed: % (%)', SQLERRM, SQLSTATE;
    RETURN false;
END;
$$;

-- Drop TTL index and cleanup
CREATE FUNCTION ttl_drop_index(
    p_table_name TEXT,
    p_column_name TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_idx_name TEXT;
BEGIN
    -- Get the index name
    SELECT index_name INTO v_idx_name
    FROM ttl_index_table
    WHERE ttl_index_table.table_name = p_table_name 
      AND ttl_index_table.column_name = p_column_name;
    
    -- Drop the index if it exists
    IF v_idx_name IS NOT NULL THEN
        EXECUTE format('DROP INDEX IF EXISTS %I', v_idx_name);
    END IF;
    
    -- Delete the configuration
    DELETE FROM ttl_index_table 
    WHERE ttl_index_table.table_name = p_table_name 
      AND ttl_index_table.column_name = p_column_name;
    
    RETURN FOUND;
END;
$$;

-- Optimized TTL runner with batch deletion and per-table transactions
CREATE OR REPLACE FUNCTION ttl_runner() RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
    batch_deleted INTEGER;
    table_deleted BIGINT;
    total_deleted INTEGER := 0;
    delete_query TEXT;
    start_time TIMESTAMPTZ;
    lock_acquired BOOLEAN;
BEGIN
    -- Concurrency control: Try to acquire advisory lock
    SELECT pg_try_advisory_lock(hashtext('pg_ttl_index_runner')) INTO lock_acquired;
    IF NOT lock_acquired THEN
        RAISE NOTICE 'TTL runner: Another instance is already running, skipping';
        RETURN 0;
    END IF;
    
    start_time := clock_timestamp();
    
    -- Process each table with its own error handling
    FOR rec IN SELECT table_name, column_name, expire_after_seconds, batch_size 
               FROM ttl_index_table WHERE active = true
               ORDER BY table_name, column_name
    LOOP
        table_deleted := 0;
        
        BEGIN
            -- Batch deletion loop
            LOOP
                -- Delete in batches using ctid for efficiency
                delete_query := format(
                    'DELETE FROM %I WHERE ctid = ANY(ARRAY(
                        SELECT ctid FROM %I 
                        WHERE %I < clock_timestamp() - INTERVAL ''%s seconds''
                        LIMIT %s
                    ))',
                    rec.table_name, rec.table_name, rec.column_name, 
                    rec.expire_after_seconds, rec.batch_size
                );
                
                EXECUTE delete_query;
                GET DIAGNOSTICS batch_deleted = ROW_COUNT;
                
                table_deleted := table_deleted + batch_deleted;
                total_deleted := total_deleted + batch_deleted;
                
                -- Exit loop when no more rows to delete
                EXIT WHEN batch_deleted = 0;
                
                -- Yield to other processes between batches
                PERFORM pg_sleep(0.01);
            END LOOP;
            
            -- Update stats for this table
            UPDATE ttl_index_table 
            SET last_run = start_time,
                rows_deleted_last_run = table_deleted,
                total_rows_deleted = ttl_index_table.total_rows_deleted + table_deleted
            WHERE ttl_index_table.table_name = rec.table_name 
              AND ttl_index_table.column_name = rec.column_name;
              
        EXCEPTION WHEN OTHERS THEN
            -- Log error but continue with other tables
            RAISE WARNING 'TTL runner: Failed to cleanup table %.%: % (%)', 
                         rec.table_name, rec.column_name, SQLERRM, SQLSTATE;
        END;
    END LOOP;
    
    -- Release advisory lock
    PERFORM pg_advisory_unlock(hashtext('pg_ttl_index_runner'));
    
    RETURN total_deleted;
END;
$$;

-- C functions for worker management
CREATE FUNCTION ttl_start_worker() RETURNS BOOLEAN
LANGUAGE C STRICT
AS 'MODULE_PATHNAME';

CREATE FUNCTION ttl_stop_worker() RETURNS BOOLEAN
LANGUAGE C STRICT
AS 'MODULE_PATHNAME';

-- Worker status function
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

-- Enhanced summary with stats
CREATE OR REPLACE FUNCTION ttl_summary()
RETURNS TABLE(
    table_name TEXT,
    column_name TEXT,
    expire_after_seconds INTEGER,
    batch_size INTEGER,
    active BOOLEAN,
    last_run TIMESTAMPTZ,
    time_since_last_run INTERVAL,
    rows_deleted_last_run BIGINT,
    total_rows_deleted BIGINT,
    index_name TEXT
)
LANGUAGE sql
AS $$
    SELECT 
        t.table_name,
        t.column_name,
        t.expire_after_seconds,
        t.batch_size,
        t.active,
        t.last_run,
        CASE 
            WHEN t.last_run IS NOT NULL THEN NOW() - t.last_run
            ELSE NULL
        END as time_since_last_run,
        t.rows_deleted_last_run,
        t.total_rows_deleted,
        t.index_name
    FROM ttl_index_table t
    ORDER BY t.table_name, t.column_name;
$$;