---
sidebar_position: 1
---

# Functions Reference

Complete API reference for all `pg_ttl_index` functions.

## TTL Management Functions

### ttl_create_index()

Creates or updates a TTL index configuration for automatic data expiration.

#### Signature

```sql
ttl_create_index(
    p_table_name TEXT,
    p_column_name TEXT,
    p_expire_after_seconds INTEGER,
    p_batch_size INTEGER DEFAULT 10000
) RETURNS BOOLEAN
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_table_name` | TEXT | Yes | Name of the table to apply TTL to |
| `p_column_name` | TEXT | Yes | Name of the timestamp column for expiration |
| `p_expire_after_seconds` | INTEGER | Yes | Number of seconds before data expires |
| `p_batch_size` | INTEGER | No | Rows to delete per batch (default: 10000) |

#### Return Value

- `true` - TTL index created/updated successfully
- `false` - Operation failed (check logs for details)

#### Behavior

1. **Creates an index** on the timestamp column if it doesn't exist
   - Index name: `idx_ttl_{table}_{column}`
2. **Registers or updates** the TTL configuration in `ttl_index_table`
3. **Activates** automatic cleanup for the table
4. **Idempotent** - Safe to call multiple times (updates configuration)

#### Examples

**Basic usage:**
```sql
-- Sessions expire after 1 hour
SELECT ttl_create_index('user_sessions', 'created_at', 3600);
```

**With custom batch size:**
```sql
-- High-volume table with large batch size
SELECT ttl_create_index('app_logs', 'logged_at', 604800, 50000);
```

**Immediate expiration (cache use case):**
```sql
-- Expire based on expires_at column
SELECT ttl_create_index('cache_entries', 'expires_at', 0);
```

**Update existing TTL:**
```sql
-- Change expiry from 1 hour to 2 hours
SELECT ttl_create_index('user_sessions', 'created_at', 7200);
```

#### Error Handling

The function returns `false` on error and logs warnings:
```sql
WARNING:  TTL create_index failed: column "invalid_col" does not exist
```

---

### ttl_drop_index()

Removes a TTL index configuration and drops the associated index.

#### Signature

```sql
ttl_drop_index(
    p_table_name TEXT,
    p_column_name TEXT
) RETURNS BOOLEAN
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_table_name` | TEXT | Yes | Name of the table |
| `p_column_name` | TEXT | Yes | Name of the timestamp column |

#### Return Value

- `true` - TTL index removed successfully
- `false` - No matching TTL index found

#### Behavior

1. **Drops the auto-created index** if it exists
2. **Removes the configuration** from `ttl_index_table`
3. **Stops automatic cleanup** for this table/column

#### Examples

```sql
-- Remove TTL from sessions table
SELECT ttl_drop_index('user_sessions', 'created_at');

-- Verify removal
SELECT * FROM ttl_summary();
```

---

### ttl_runner()

Manually executes TTL cleanup for all active TTL indexes.

#### Signature

```sql
ttl_runner() RETURNS INTEGER
```

#### Parameters

None.

#### Return Value

- `INTEGER` - Total number of rows deleted across all tables

#### Behavior

1. **Acquires advisory lock** to prevent concurrent runs
2. **Processes each active TTL index** sequentially
3. **Deletes expired rows in batches** according to configured batch size
4. **Updates statistics** (`rows_deleted_last_run`, `total_rows_deleted`)
5. **Per-table error handling** - errors in one table don't affect others
6. **Releases advisory lock** when complete

#### Examples

```sql
-- Manually trigger cleanup
SELECT ttl_runner();
-- Returns: 1523 (total rows deleted)

-- View deletion details
SELECT * FROM ttl_summary();
```

#### Performance Notes

- Uses `ctid` for efficient batch deletion
- Sleeps 10ms between batches to yield to other processes
- Skips run if another instance is already running (via advisory lock)

---

## Worker Management Functions

### ttl_start_worker()

Starts the background worker for automatic TTL cleanup.

#### Signature

```sql
ttl_start_worker() RETURNS BOOLEAN
```

#### Parameters

None.

#### Return Value

- `true` - Worker started successfully
- `false` - Failed to start worker

#### Behavior

- Launches a dedicated background worker for the current database
- Worker runs `ttl_runner()` every `pg_ttl_index.naptime` seconds (default: 60)
- **Must be called manually** per database (not automatic)
- Only one worker runs per database

#### Examples

```sql
-- Start the worker
SELECT ttl_start_worker();

-- Verify it's running
SELECT * FROM ttl_worker_status();
```

:::warning Important
The worker **does not persist** across PostgreSQL restarts. You must start it again after server restart.
:::

---

### ttl_stop_worker()

Stops the background worker for TTL cleanup.

#### Signature

```sql
ttl_stop_worker() RETURNS BOOLEAN
```

#### Parameters

None.

#### Return Value

- `true` - Worker stopped successfully
- `false` - No worker was running

#### Behavior

- Terminates the background worker for the current database
- Cleanup will no longer run automatically
- TTL configurations remain in `ttl_index_table`

#### Examples

```sql
-- Stop the worker
SELECT ttl_stop_worker();

-- Verify it stopped
SELECT * FROM ttl_worker_status();
-- Should return no rows
```

---

## Monitoring Functions

### ttl_worker_status()

Returns the status of TTL background workers.

#### Signature

```sql
ttl_worker_status() RETURNS TABLE(
    worker_pid INTEGER,
    application_name TEXT,
    state TEXT,
    backend_start TIMESTAMPTZ,
    state_change TIMESTAMPTZ,
    query_start TIMESTAMPTZ,
    database_name TEXT
)
```

#### Parameters

None.

#### Return Columns

| Column | Type | Description |
|--------|------|-------------|
| `worker_pid` | INTEGER | Process ID of the worker |
| `application_name` | TEXT | Always "TTL Worker DB \{dbname\}" |
| `state` | TEXT | Current state (usually "idle") |
| `backend_start` | TIMESTAMPTZ | When the worker started |
| `state_change` | TIMESTAMPTZ | Last state change time |
| `query_start` | TIMESTAMPTZ | When current query started |
| `database_name` | TEXT | Database name |

#### Examples

```sql
-- Check if worker is running
SELECT 
    worker_pid,
    state,
    backend_start,
    NOW() - backend_start AS uptime
FROM ttl_worker_status();
```

**Output:**
```
 worker_pid |  state  |        backend_start        |     uptime
------------+---------+-----------------------------+-----------------
      12345 | idle    | 2026-01-03 02:00:00+00      | 00:42:15.123
```

---

### ttl_summary()

Returns a comprehensive summary of all TTL configurations and statistics.

#### Signature

```sql
ttl_summary() RETURNS TABLE(
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
```

#### Parameters

None.

#### Return Columns

| Column | Type | Description |
|--------|------|-------------|
| `table_name` | TEXT | Table with TTL enabled |
| `column_name` | TEXT | Timestamp column used for expiration |
| `expire_after_seconds` | INTEGER | Expiration time in seconds |
| `batch_size` | INTEGER | Rows deleted per batch |
| `active` | BOOLEAN | Whether TTL is active |
| `last_run` | TIMESTAMPTZ | When cleanup last ran |
| `time_since_last_run` | INTERVAL | Time since last cleanup |
| `rows_deleted_last_run` | BIGINT | Rows deleted in last run |
| `total_rows_deleted` | BIGINT | Total rows deleted all-time |
| `index_name` | TEXT | Name of the auto-created index |

#### Examples

**Basic monitoring:**
```sql
SELECT 
    table_name,
    expire_after_seconds / 3600.0 AS expire_hours,
    rows_deleted_last_run,
    total_rows_deleted
FROM ttl_summary();
```

**Active tables only:**
```sql
SELECT * FROM ttl_summary() WHERE active = true;
```

**Recent activity:**
```sql
SELECT 
    table_name,
    last_run,
    time_since_last_run,
    rows_deleted_last_run
FROM ttl_summary()
WHERE last_run > NOW() - INTERVAL '1 hour'
ORDER BY last_run DESC;
```

---

## Function Usage Patterns

### Complete Setup Workflow

```sql
-- 1. Start worker
SELECT ttl_start_worker();

-- 2. Create TTL indexes
SELECT ttl_create_index('sessions', 'created_at', 1800);
SELECT ttl_create_index('logs', 'logged_at', 604800);

-- 3. Monitor
SELECT * FROM ttl_summary();
SELECT * FROM ttl_worker_status();
```

### Maintenance Workflow

```sql
-- Check worker health
SELECT * FROM ttl_worker_status();

-- Review cleanup statistics
SELECT 
    table_name,
    time_since_last_run,
    rows_deleted_last_run
FROM ttl_summary()
WHERE active = true;

-- Manual cleanup if needed
SELECT ttl_runner();
```

### Disable/Enable Workflow

```sql
-- Disable TTL temporarily
UPDATE ttl_index_table 
SET active = false 
WHERE table_name = 'sessions';

-- Or stop worker completely
SELECT ttl_stop_worker();

-- Re-enable
UPDATE ttl_index_table 
SET active = true 
WHERE table_name = 'sessions';
SELECT ttl_start_worker();
```

## See Also

- [Configuration Parameters](configuration.md) - GUC settings
- [Tables Reference](tables.md) - `ttl_index_table` schema
- [Monitoring Guide](../guides/monitoring.md) - Detailed monitoring strategies
