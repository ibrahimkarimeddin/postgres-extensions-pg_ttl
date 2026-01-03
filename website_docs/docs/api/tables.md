---
sidebar_position: 2
---

# Tables Reference

Internal tables and schema used by `pg_ttl_index`.

## ttl_index_table

The main configuration and statistics table for TTL indexes.

### Schema

```sql
CREATE TABLE ttl_index_table (
    table_name TEXT NOT NULL,
    column_name TEXT NOT NULL,
    expire_after_seconds INTEGER NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_run TIMESTAMPTZ,
    batch_size INTEGER NOT NULL DEFAULT 10000,
    rows_deleted_last_run BIGINT DEFAULT 0,
    total_rows_deleted BIGINT DEFAULT 0,
    index_name TEXT,
    PRIMARY KEY (table_name, column_name)
);
```

### Columns

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `table_name` | TEXT | No | - | Name of the table with TTL enabled  |
| `column_name` | TEXT | No | - | Timestamp column name for expiration |
| `expire_after_seconds` | INTEGER | No | - | Seconds before data expires |
| `active` | BOOLEAN | No | `true` | Whether TTL is currently active |
| `created_at` | TIMESTAMPTZ | No | `NOW()` | When TTL was first created |
| `updated_at` | TIMESTAMPTZ | Yes | `NOW()` | Last configuration update |
| `last_run` | TIMESTAMPTZ | Yes | `NULL` | Last cleanup execution time |
| `batch_size` | INTEGER | No | `10000` | Rows to delete per batch |
| `rows_deleted_last_run` | BIGINT | Yes | `0` | Rows deleted in last cleanup |
| `total_rows_deleted` | BIGINT | Yes | `0` | Total rows deleted all-time |
| `index_name` | TEXT | Yes | `NULL` | Name of auto-created index |

### Primary Key

`(table_name, column_name)` - Ensures one TTL configuration per table/column pair.

## Querying ttl_index_table

### View All TTL Configurations

```sql
SELECT * FROM ttl_index_table
ORDER BY table_name, column_name;
```

### Active TTL Indexes Only

```sql
SELECT table_name, column_name, expire_after_seconds
FROM ttl_index_table
WHERE active = true;
```

### Recent Activity

```sql
SELECT 
    table_name,
    last_run,
    NOW() - last_run AS time_since_last,
    rows_deleted_last_run
FROM ttl_index_table
WHERE last_run IS NOT NULL
ORDER BY last_run DESC;
```

### Tables with High Deletion Rate

```sql
SELECT 
    table_name,
    total_rows_deleted,
    rows_deleted_last_run
FROM ttl_index_table
ORDER BY total_rows_deleted DESC
LIMIT 10;
```

## Direct Manipulation (Advanced)

:::warning Advanced Usage
Direct manipulation is for advanced users. Use the [API functions](functions.md) for normal operations.
:::

### Temporarily Disable TTL

```sql
-- Disable cleanup without removing configuration
UPDATE ttl_index_table
SET active = false
WHERE table_name = 'user_sessions';
```

### Change Expiry Time

```sql
-- Update expiration period
UPDATE ttl_index_table
SET expire_after_seconds = 7200,  -- 2 hours
    updated_at = NOW()
WHERE table_name = 'user_sessions'
  AND column_name = 'created_at';
```

### Adjust Batch Size

```sql
-- Increase batch size for better performance
UPDATE ttl_index_table
SET batch_size = 50000
WHERE table_name = 'app_logs';
```

### Reset Statistics

```sql
-- Reset deletion counters
UPDATE ttl_index_table
SET rows_deleted_last_run = 0,
    total_rows_deleted = 0
WHERE table_name = 'user_sessions';
```

### Re-enable TTL

```sql
-- Re-activate disabled TTL
UPDATE ttl_index_table
SET active = true,
    updated_at = NOW()
WHERE table_name = 'user_sessions';
```

## Monitoring Queries

### Tables Never Cleaned

```sql
SELECT 
    table_name,
    column_name,
    created_at,
    NOW() - created_at AS age
FROM ttl_index_table
WHERE last_run IS NULL
  AND active = true;
```

### Stale Cleanup Detection

```sql
-- Find tables where cleanup hasn't run recently
SELECT 
    table_name,
    last_run,
    NOW() - last_run AS time_since_cleanup
FROM ttl_index_table
WHERE active = true
  AND last_run < NOW() - INTERVAL '5 minutes'
ORDER BY last_run;
```

### Deletion Efficiency

```sql
-- Average rows deleted per run
SELECT 
    table_name,
    total_rows_deleted,
    CASE 
        WHEN last_run > created_at 
        THEN total_rows_deleted::FLOAT / 
             EXTRACT(EPOCH FROM (last_run - created_at)) * 60
        ELSE 0
    END AS avg_rows_per_minute
FROM ttl_index_table
WHERE active = true;
```

## Schema Notes

### Indexing Strategy

The `ttl_index_table` itself is small (typically < 100 rows) and doesn't require additional indexes. The primary key on `(table_name, column_name)` provides efficient lookups.

### Statistics Tracking

Statistics (`rows_deleted_last_run`, `total_rows_deleted`) are updated after each cleanup run. These counters:
- Are **cumulative** for `total_rows_deleted`
- Reset on each run for `rows_deleted_last_run`
- Never overflow (using BIGINT type)

### Active Flag

The `active` flag allows you to:
- Temporarily disable TTL without losing configuration
- Re-enable later without reconfiguring
- Keep historical data (created_at, total_rows_deleted)

## Best Practices

### Don't Bypass the API

Use [`ttl_create_index()`](functions.md#ttl_create_index) and [`ttl_drop_index()`](functions.md#ttl_drop_index) instead of direct INSERT/DELETE:

❌ **Bad:**
```sql
INSERT INTO ttl_index_table (table_name, column_name, expire_after_seconds)
VALUES ('my_table', 'created_at', 3600);
```

✅ **Good:**
```sql
SELECT ttl_create_index('my_table', 'created_at', 3600);
```

### Use ttl_summary() for Monitoring

Instead of querying `ttl_index_table` directly, use [`ttl_summary()`](functions.md#ttl_summary) which includes computed fields:

✅ **Better:**
```sql
SELECT * FROM ttl_summary();
```

### Backup TTL Configuration

Include `ttl_index_table` in your backup strategy:

```sql
-- Export TTL configuration
COPY ttl_index_table TO '/backup/ttl_config.csv' CSV HEADER;

-- Restore TTL configuration
COPY ttl_index_table FROM '/backup/ttl_config.csv' CSV HEADER;
```

## See Also

- [Functions API](functions.md) - Recommended way to manage TTL
- [Monitoring Guide](../guides/monitoring.md) - How to track TTL activity
- [Best Practices](../guides/best-practices.md) - Optimization tips
