CREATE TABLE ttl_index_table (
    schema_name TEXT NOT NULL DEFAULT 'public',
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
    soft_delete_column TEXT,
    index_created_by_extension BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (schema_name, table_name, column_name)
);

-- Create TTL index with auto-indexing
CREATE FUNCTION ttl_create_index(
    p_table_name TEXT,
    p_column_name TEXT,
    p_expire_after_seconds INTEGER,
    p_batch_size INTEGER DEFAULT 10000,
    p_soft_delete_column TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    v_idx_name TEXT;
    v_generated_idx_name TEXT;
    v_existing_idx_name TEXT;
    v_prev_idx_name TEXT;
    v_prev_index_created_by_extension BOOLEAN;
    v_index_created_by_extension BOOLEAN;
    v_table_oid OID;
    v_table_schema TEXT;
    v_table_name TEXT;
    v_column_exists BOOLEAN;
    v_soft_delete_typname TEXT;
BEGIN
    IF p_table_name IS NULL OR p_table_name = '' THEN
        RAISE EXCEPTION 'Table name cannot be empty';
    END IF;

    IF p_column_name IS NULL OR p_column_name = '' THEN
        RAISE EXCEPTION 'Column name cannot be empty';
    END IF;

    IF p_batch_size <= 0 THEN
        RAISE EXCEPTION 'Batch size must be greater than 0';
    END IF;

    IF p_expire_after_seconds < 0 THEN
        RAISE EXCEPTION 'expire_after_seconds must be >= 0';
    END IF;

    v_table_oid := pg_catalog.to_regclass(p_table_name);
    IF v_table_oid IS NULL THEN
        RAISE EXCEPTION 'Table "%" was not found. Use a schema-qualified name (e.g. myschema.mytable).',
                        p_table_name;
    END IF;

    SELECT n.nspname, c.relname
    INTO v_table_schema, v_table_name
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n
      ON n.oid = c.relnamespace
    WHERE c.oid = v_table_oid
      AND c.relkind IN ('r', 'p');

    IF v_table_schema IS NULL THEN
        RAISE EXCEPTION 'Object "%" is not a regular or partitioned table', p_table_name;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute a
        WHERE a.attrelid = v_table_oid
          AND a.attname = p_column_name
          AND a.attnum > 0
          AND NOT a.attisdropped
    ) INTO v_column_exists;

    IF NOT v_column_exists THEN
        RAISE EXCEPTION 'Column "%" does not exist on table %.%', p_column_name, v_table_schema, v_table_name;
    END IF;

    IF p_soft_delete_column IS NOT NULL THEN
        IF p_soft_delete_column = p_column_name THEN
            RAISE EXCEPTION 'soft_delete_column cannot be the same as TTL column';
        END IF;

        SELECT t.typname
        INTO v_soft_delete_typname
        FROM pg_catalog.pg_attribute a
        JOIN pg_catalog.pg_type t
          ON t.oid = a.atttypid
        WHERE a.attrelid = v_table_oid
          AND a.attname = p_soft_delete_column
          AND a.attnum > 0
          AND NOT a.attisdropped;

        IF v_soft_delete_typname IS NULL THEN
            RAISE EXCEPTION 'Soft delete column "%" does not exist on table %.%',
                            p_soft_delete_column, v_table_schema, v_table_name;
        END IF;

        IF v_soft_delete_typname NOT IN ('timestamp', 'timestamptz') THEN
            RAISE EXCEPTION 'Soft delete column "%" must be timestamp or timestamptz',
                            p_soft_delete_column;
        END IF;
    END IF;

    -- Create index name
    v_generated_idx_name := 'idx_ttl_' || v_table_name || '_' || p_column_name;

    -- Keep ownership stable across repeated updates.
    SELECT index_name, index_created_by_extension
    INTO v_prev_idx_name, v_prev_index_created_by_extension
    FROM ttl_index_table
    WHERE ttl_index_table.schema_name = v_table_schema
      AND ttl_index_table.table_name = v_table_name
      AND ttl_index_table.column_name = p_column_name;

    IF COALESCE(v_prev_index_created_by_extension, false) THEN
        v_idx_name := COALESCE(v_prev_idx_name, v_generated_idx_name);
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I.%I (%I)',
                       v_idx_name, v_table_schema, v_table_name, p_column_name);
        v_index_created_by_extension := true;
    ELSE
        -- Reuse any existing valid/ready index that already includes the TTL column.
        SELECT idx.relname
        INTO v_existing_idx_name
        FROM pg_catalog.pg_index i
        JOIN pg_catalog.pg_class idx
          ON idx.oid = i.indexrelid
        JOIN pg_catalog.pg_attribute a
          ON a.attrelid = i.indrelid
         AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = v_table_oid
          AND a.attname = p_column_name
          AND i.indisvalid
          AND i.indisready
        ORDER BY idx.relname
        LIMIT 1;

        IF v_existing_idx_name IS NOT NULL THEN
            v_idx_name := v_existing_idx_name;
            v_index_created_by_extension := false;
        ELSE
            v_idx_name := v_generated_idx_name;
            EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I.%I (%I)',
                           v_idx_name, v_table_schema, v_table_name, p_column_name);
            v_index_created_by_extension := true;
        END IF;
    END IF;

    -- Insert or update TTL configuration
    INSERT INTO ttl_index_table (schema_name, table_name, column_name, expire_after_seconds,
                                 batch_size, index_name, soft_delete_column,
                                 index_created_by_extension, active, created_at)
    VALUES (v_table_schema, v_table_name, p_column_name, p_expire_after_seconds,
            p_batch_size, v_idx_name, p_soft_delete_column, v_index_created_by_extension, true, NOW())
    ON CONFLICT (schema_name, table_name, column_name) DO UPDATE SET
        expire_after_seconds = p_expire_after_seconds,
        batch_size = p_batch_size,
        index_name = EXCLUDED.index_name,
        soft_delete_column = EXCLUDED.soft_delete_column,
        index_created_by_extension = EXCLUDED.index_created_by_extension,
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
SET search_path FROM CURRENT
AS $$
DECLARE
    v_idx_name TEXT;
    v_index_created_by_extension BOOLEAN;
    v_table_oid OID;
    v_table_schema TEXT;
    v_table_name TEXT;
BEGIN
    IF p_table_name IS NULL OR p_table_name = '' THEN
        RAISE EXCEPTION 'Table name cannot be empty';
    END IF;

    IF p_column_name IS NULL OR p_column_name = '' THEN
        RAISE EXCEPTION 'Column name cannot be empty';
    END IF;

    v_table_oid := pg_catalog.to_regclass(p_table_name);
    IF v_table_oid IS NULL THEN
        RAISE EXCEPTION 'Table "%" was not found. Use a schema-qualified name (e.g. myschema.mytable).',
                        p_table_name;
    END IF;

    SELECT n.nspname, c.relname
    INTO v_table_schema, v_table_name
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n
      ON n.oid = c.relnamespace
    WHERE c.oid = v_table_oid;

    -- Get index ownership details.
    SELECT index_name, index_created_by_extension
    INTO v_idx_name, v_index_created_by_extension
    FROM ttl_index_table
    WHERE ttl_index_table.schema_name = v_table_schema
      AND ttl_index_table.table_name = v_table_name
      AND ttl_index_table.column_name = p_column_name;

    -- Drop only indexes managed by this extension.
    IF v_idx_name IS NOT NULL AND COALESCE(v_index_created_by_extension, false) THEN
        EXECUTE format('DROP INDEX IF EXISTS %I.%I', v_table_schema, v_idx_name);
    END IF;

    -- Delete the configuration
    DELETE FROM ttl_index_table
    WHERE ttl_index_table.schema_name = v_table_schema
      AND ttl_index_table.table_name = v_table_name
      AND ttl_index_table.column_name = p_column_name;

    RETURN FOUND;
END;
$$;

-- Optimized TTL runner with batch deletion and per-table transactions
CREATE OR REPLACE FUNCTION ttl_runner() RETURNS INTEGER
LANGUAGE plpgsql
SET search_path FROM CURRENT
AS $$
DECLARE
    rec RECORD;
    batch_deleted INTEGER;
    table_deleted BIGINT;
    total_deleted INTEGER := 0;
    cleanup_query TEXT;
    start_time TIMESTAMPTZ;
    lock_acquired BOOLEAN;
BEGIN
    -- Concurrency control: Try to acquire advisory lock
    SELECT pg_catalog.pg_try_advisory_lock(pg_catalog.hashtext('pg_ttl_index_runner')) INTO lock_acquired;
    IF NOT lock_acquired THEN
        RAISE NOTICE 'TTL runner: Another instance is already running, skipping';
        RETURN 0;
    END IF;

    start_time := pg_catalog.clock_timestamp();

    -- Process each table with its own error handling
    FOR rec IN SELECT schema_name, table_name, column_name, expire_after_seconds, batch_size, soft_delete_column
               FROM ttl_index_table WHERE active = true
               ORDER BY schema_name, table_name, column_name
    LOOP
        table_deleted := 0;

        BEGIN
            -- Batch deletion loop
            LOOP
                IF rec.soft_delete_column IS NULL THEN
                    -- Hard delete mode
                    cleanup_query := format(
                        'DELETE FROM %I.%I WHERE ctid = ANY(ARRAY(
                            SELECT ctid FROM %I.%I
                            WHERE %I < pg_catalog.clock_timestamp() - pg_catalog.make_interval(secs => %s)
                            LIMIT %s
                        ))',
                        rec.schema_name, rec.table_name,
                        rec.schema_name, rec.table_name,
                        rec.column_name, rec.expire_after_seconds, rec.batch_size
                    );
                ELSE
                    -- Soft delete mode: mark rows once.
                    cleanup_query := format(
                        'UPDATE %I.%I
                         SET %I = pg_catalog.clock_timestamp()
                         WHERE ctid = ANY(ARRAY(
                             SELECT ctid FROM %I.%I
                             WHERE %I < pg_catalog.clock_timestamp() - pg_catalog.make_interval(secs => %s)
                               AND %I IS NULL
                             LIMIT %s
                         ))',
                        rec.schema_name, rec.table_name,
                        rec.soft_delete_column,
                        rec.schema_name, rec.table_name,
                        rec.column_name, rec.expire_after_seconds,
                        rec.soft_delete_column, rec.batch_size
                    );
                END IF;

                EXECUTE cleanup_query;
                GET DIAGNOSTICS batch_deleted = ROW_COUNT;

                table_deleted := table_deleted + batch_deleted;
                total_deleted := total_deleted + batch_deleted;

                -- Exit loop when no more rows to delete
                EXIT WHEN batch_deleted = 0;

                -- Yield to other processes between batches
                PERFORM pg_catalog.pg_sleep(0.01);
            END LOOP;

            -- Update stats for this table
            UPDATE ttl_index_table
            SET last_run = start_time,
                rows_deleted_last_run = table_deleted,
                total_rows_deleted = ttl_index_table.total_rows_deleted + table_deleted
            WHERE ttl_index_table.schema_name = rec.schema_name
              AND ttl_index_table.table_name = rec.table_name
              AND ttl_index_table.column_name = rec.column_name;

        EXCEPTION WHEN OTHERS THEN
            -- Log error but continue with other tables
            RAISE WARNING 'TTL runner: Failed to cleanup table %.%.%: % (%)',
                         rec.schema_name, rec.table_name, rec.column_name, SQLERRM, SQLSTATE;
        END;
    END LOOP;

    -- Release advisory lock
    PERFORM pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('pg_ttl_index_runner'));

    RETURN total_deleted;
END;
$$;

-- C functions for worker management
CREATE FUNCTION ttl_start_worker() RETURNS BOOLEAN
LANGUAGE C STRICT
SET search_path FROM CURRENT
AS 'MODULE_PATHNAME';

CREATE FUNCTION ttl_stop_worker() RETURNS BOOLEAN
LANGUAGE C STRICT
SET search_path FROM CURRENT
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
SET search_path FROM CURRENT
AS $$
    SELECT
        pid::INTEGER as worker_pid,
        application_name::TEXT,
        state::TEXT,
        backend_start,
        state_change,
        query_start,
        datname::TEXT as database_name
    FROM pg_catalog.pg_stat_activity
    WHERE application_name LIKE 'TTL Worker DB %'
    ORDER BY backend_start DESC;
$$;

-- Enhanced summary with stats
CREATE OR REPLACE FUNCTION ttl_summary()
RETURNS TABLE(
    schema_name TEXT,
    table_name TEXT,
    column_name TEXT,
    expire_after_seconds INTEGER,
    batch_size INTEGER,
    active BOOLEAN,
    last_run TIMESTAMPTZ,
    time_since_last_run INTERVAL,
    rows_deleted_last_run BIGINT,
    total_rows_deleted BIGINT,
    index_name TEXT,
    soft_delete_column TEXT,
    cleanup_mode TEXT
)
LANGUAGE sql
SET search_path FROM CURRENT
AS $$
    SELECT
        t.schema_name,
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
        t.index_name,
        t.soft_delete_column,
        CASE
            WHEN t.soft_delete_column IS NULL THEN 'hard_delete'
            ELSE 'soft_delete'
        END AS cleanup_mode
    FROM ttl_index_table t
    ORDER BY t.schema_name, t.table_name, t.column_name;
$$;
