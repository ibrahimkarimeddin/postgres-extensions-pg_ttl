---
sidebar_position: 2
---

# Performance Tuning

Optimize `pg_ttl_index` for maximum performance and minimal impact.

## Quick Wins

### 1. Right-Size Batch Deletions

```sql
-- Check current batch effectiveness
SELECT 
    table_name,
    batch_size,
    rows_deleted_last_run,
    rows_deleted_last_run::FLOAT / batch_size AS ratio
FROM ttl_summary()
ORDER BY ratio DESC;

-- If ratio consistently > 0.9, increase batch_size
UPDATE ttl_index_table
SET batch_size = 50000
WHERE table_name = 'high_volume_table';
```

### 2. Tune Cleanup Interval

```sql
-- Less frequent = lower overhead
ALTER SYSTEM SET pg_ttl_index.naptime = 120;  -- 2 minutes
SELECT pg_reload_conf();
```

### 3. Use Partitioning

```sql
-- Combine partitioning with TTL for huge tables
CREATE TABLE events (
    id BIGSERIAL,
    data JSONB,
    created_at TIMESTAMPTZ
) PARTITION BY RANGE (created_at);

-- Drop entire partitions instead of row-level deletions
```

## Batch Size Tuning

### Benchmarking Formula

```
Target batch size = (rows inserted per hour / 60) × 2
```

**Example**:
- 120,000 rows/hour inserted
- Cleanup runs every 60 seconds
- Expected deletions/run: 120,000 / 60 = 2,000
- Recommended batch: 2,000 × 2 = **4,000**

### Finding Optimal Batch Size

```sql
-- Test different batch sizes in development
SELECT ttl_create_index('test_table', 'created_at', 3600, 10000);
-- Monitor performance, adjust

SELECT ttl_create_index('test_table', 'created_at', 3600, 25000);
-- Re-test

SELECT ttl_create_index('test_table', 'created_at', 3600, 50000);
-- Compare results
```

### Batch Size Impact

| Batch Size | CPU Usage | Lock Duration | WAL Generated |
|------------|-----------|---------------|---------------|
| 1,000      | Low       | Very Short    | Low           |
| 10,000     | Medium    | Short         | Medium        |
| 50,000     | Higher    | Medium        | High          |
| 100,000    | High      | Long          | Very High     |

## Index Optimization

### Leverage Auto-Created Indexes

```sql
-- TTL uses the auto-created index efficiently
SELECT ttl_create_index('logs', 'created_at', 604800);
-- Creates: idx_ttl_logs_created_at

-- Verify index is used
EXPLAIN SELECT ctid FROM logs WHERE created_at < NOW() - INTERVAL '7 days';
-- Should show "Index Scan using idx_ttl_logs_created_at"
```

### Composite Indexes for Queries

```sql
-- If you frequently query by user + timestamp:
CREATE INDEX idx_logs_user_time ON logs(user_id, created_at);

-- TTL still benefits from its own index for cleanup
SELECT ttl_create_index('logs', 'created_at', 604800);
```

### Index Maintenance

```sql
-- Periodically reindex TTL indexes
REINDEX INDEX idx_ttl_sessions_created_at;

-- Or use auto_vacuum aggressively
ALTER TABLE sessions SET (autovacuum_vacuum_scale_factor = 0.05);
```

## Monitoring Performance

### Track Cleanup Duration

```sql
-- Add timing to cleanup runs
CREATE OR REPLACE FUNCTION ttl_runner_timed()
RETURNS TABLE(duration INTERVAL, rows_deleted INTEGER) AS $$
DECLARE
    start_time TIMESTAMPTZ;
    result INTEGER;
BEGIN
    start_time := clock_timestamp();
    SELECT ttl_runner() INTO result;
    RETURN QUERY SELECT clock_timestamp() - start_time, result;
END;
$$ LANGUAGE plpgsql;

-- Test it
SELECT * FROM ttl_runner_timed();
```

### Identify Slow Tables

```sql
-- Which tables take longest to clean?
-- (requires custom logging)

-- Instead, check row counts vs batch size
SELECT 
    table_name,
    rows_deleted_last_run,
    batch_size,
    CEILING(rows_deleted_last_run::NUMERIC / batch_size) AS batches_needed
FROM ttl_summary()
ORDER BY batches_needed DESC;
```

## Reducing I/O Impact

### Spread Out Cleanup

```sql
-- Increase naptime to reduce frequency
ALTER SYSTEM SET pg_ttl_index.naptime = 180;  -- 3 minutes
SELECT pg_reload_conf();
```

### Use Off-Peak Hours

```sql
-- Disable during peak hours (8am-6pm)
-- Schedule via cron or pgAgent

-- 8am: Disable
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();

-- 6pm: Enable
ALTER SYSTEM SET pg_ttl_index.enabled = true;
SELECT pg_reload_conf();
```

### Maintenance Window Cleanup

```sql
-- Disable automatic cleanup
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();

-- Manual cleanup during maintenance window
SELECT ttl_runner();
```

## High-Volume Scenarios

### Streaming Data

```sql
-- High-frequency inserts (100K+ rows/hour)
SELECT ttl_create_index('streaming_data', 'timestamp', 3600, 100000);

-- Frequent cleanup
ALTER SYSTEM SET pg_ttl_index.naptime = 30;
SELECT pg_reload_conf();
```

### Time-Series Data

```sql
-- Partition by time period
CREATE TABLE metrics (
    id BIGSERIAL,
    value NUMERIC,
    timestamp TIMESTAMPTZ
) PARTITION BY RANGE (timestamp);

-- Create partitions monthly
-- Drop old partitions instead of row-level TTL
DROP TABLE metrics_2025_12;
```

## WAL Reduction

### Unlogged Tables (Caution!)

```sql
-- For truly temporary data only
CREATE UNLOGGED TABLE temp_cache (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

SELECT ttl_create_index('temp_cache', 'created_at', 300);
-- No WAL generated, but data lost on crash!
```

### Fillfactor Tuning

```sql
-- Reduce table bloat from frequent deletes
ALTER TABLE sessions SET (fillfactor = 70);

-- More free space per page = less bloat
```

## Memory Usage

### Connection Pooling

```sql
-- TTL worker uses one connection
-- Ensure max_connections accounts for it

SHOW max_connections;
-- Should be: (app connections) + 1 (for TTL worker)
```

### Shared Buffers

```sql
-- TTL benefits from cached indexes
-- Ensure sufficient shared_buffers

SHOW shared_buffers;
-- Recommended: 25% of RAM (PostgreSQL standard)
```

## Benchmarking

### Measure Baseline

```sql
-- Before optimization
SELECT 
    table_name,
    total_rows_deleted,
    last_run
FROM ttl_summary();

-- Measure over 1 hour
-- Record: rows deleted, CPU usage, I/O usage
```

### Test Optimizations

```sql
-- Change batch size
UPDATE ttl_index_table SET batch_size = 50000 WHERE table_name = 'test';

-- Measure again after 1 hour
-- Compare metrics
```

### Performance Metrics

| Metric | Target | Monitoring |
|--------|--------|------------|
| Cleanup duration | < 1 second per table | Custom timing function |
| Rows/second deleted | > 10,000 | `rows_deleted / duration` |
| CPU during cleanup | < 20% | `top`, `pg_stat_activity` |
| Lock wait time | < 100ms | `pg_stat_activity` |

## Production Tuning Examples

### E-Commerce Site

```sql
-- High session churn
SELECT ttl_create_index('sessions', 'updated_at', 1800, 25000);

-- Moderate log volume
SELECT ttl_create_index('access_logs', 'timestamp', 86400, 50000);

-- Background worker: every 30 seconds
ALTER SYSTEM SET pg_ttl_index.naptime = 30;
```

### Analytics Platform

```sql
-- Massive event streams
SELECT ttl_create_index('events', 'timestamp', 3600, 100000);

-- Aggregated data (slower cleanup OK)
SELECT ttl_create_index('hourly_stats', 'hour', 604800, 10000);

-- Background worker: every 2 minutes (reduce overhead)
ALTER SYSTEM SET pg_ttl_index.naptime = 120;
```

## Troubleshooting Performance

### Cleanup Takes Too Long

**Symptoms**: `ttl_runner()` execution > 5 seconds

**Solutions**:
1. Increase batch size
2. Add indexes on timestamp column (auto-created, but verify)
3. Run `VACUUM ANALYZE` on tables
4. Check for table bloat

### High CPU Usage

**Symptoms**: CPU spikes during cleanup

**Solutions**:
1. Increase `naptime` (less frequent cleanup)
2. Decrease `batch_size` (smaller batches)
3. Run cleanup during off-peak hours

### Table Bloat

**Symptoms**: Table size doesn't decrease despite deletions

**Solutions**:
```sql
-- More aggressive autovacuum
ALTER TABLE sessions SET (
    autovacuum_vacuum_scale_factor = 0.05,
    autovacuum_vacuum_cost_delay = 10
);

-- Manual vacuum
VACUUM FULL sessions;  -- Locks table, use with caution
```

## See Also

- [Best Practices](../guides/best-practices.md) - General optimization tips
- [Monitoring](../guides/monitoring.md) - Track performance
- [Architecture](architecture.md) - How cleanup works internally
