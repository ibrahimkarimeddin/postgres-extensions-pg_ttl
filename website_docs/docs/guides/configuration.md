---
sidebar_position: 1
---

# Configuration Guide

Fine-tune `pg_ttl_index` for optimal performance and behavior.

## Background Worker Configuration

### Cleanup Interval

Control how often cleanup runs:

```sql
-- Default: every 60 seconds
SHOW pg_ttl_index.naptime;

-- Faster cleanup (30 seconds)
ALTER SYSTEM SET pg_ttl_index.naptime = 30;
SELECT pg_reload_conf();

-- Slower cleanup (5 minutes)
ALTER SYSTEM SET pg_ttl_index.naptime = 300;
SELECT pg_reload_conf();
```

**Choose based on your workload:**
- High-volume inserts → Lower naptime (30s)
- Low-volume tables → Higher naptime (300s)
- Standard workload → Default (60s)

### Enable/Disable Worker

```sql
-- Disable background worker globally
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();

-- Re-enable
ALTER SYSTEM SET pg_ttl_index.enabled = true;
SELECT pg_reload_conf();
```

## Per-Table Configuration

### Setting Expiration Time

```sql
-- 30 minutes (sessions)
SELECT ttl_create_index('sessions', 'created_at', 1800);

-- 1 hour (short-term cache)
SELECT ttl_create_index('cache', 'expires_at', 3600);

-- 7 days (application logs)
SELECT ttl_create_index('logs', 'logged_at', 604800);

-- 30 days (audit trail)
SELECT ttl_create_index('audit', 'created_at', 2592000);
```

### Batch Size Tuning

Batch size affects performance and resource usage:

```sql
-- Small tables (< 10K rows): small batch
SELECT ttl_create_index('notifications', 'created_at', 86400, 1000);

-- Medium tables (10K-1M rows): default
SELECT ttl_create_index('sessions', 'created_at', 3600, 10000);

-- Large tables (> 1M rows): large batch
SELECT ttl_create_index('events', 'recorded_at', 604800, 50000);

-- Very high-volume tables: extra large batch
SELECT ttl_create_index('metrics', 'timestamp', 86400, 100000);
```

**Batch Size Guidelines:**

| Table Size | Deletion Rate | Recommended Batch Size |
|-----------|---------------|------------------------|
| < 10K rows | Any | 1,000 - 5,000 |
| 10K-100K rows | Low | 5,000 - 10,000 |
| 100K-1M rows | Medium | 10,000 - 25,000 |
| > 1M rows | High | 25,000 - 100,000 |

## Temporarily Disable TTL

### Disable Specific Table

```sql
-- Disable without removing configuration
UPDATE ttl_index_table
SET active = false
WHERE table_name = 'sessions';

-- Re-enable later
UPDATE ttl_index_table
SET active = true
WHERE table_name = 'sessions';
```

### Disable All TTL

```sql
-- Method 1: Stop worker
SELECT ttl_stop_worker();

-- Method 2: Disable via config
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();
```

## Update Existing Configuration

### Change Expiry Time

```sql
-- Update from 1 hour to 2 hours
SELECT ttl_create_index('sessions', 'created_at', 7200);
```

### Change Batch Size

```sql
-- Direct update
UPDATE ttl_index_table
SET batch_size = 50000
WHERE table_name = 'events';

-- Or recreate with new batch size
SELECT ttl_create_index('events', 'recorded_at', 604800, 50000);
```

## PostgreSQL Configuration File

### postgresql.conf Settings

```conf
# Required: Load extension at startup
shared_preload_libraries = 'pg_ttl_index'

# Optional: Tune behavior
pg_ttl_index.naptime = 60       # Cleanup every 60 seconds
pg_ttl_index.enabled = true     # Enable background worker
```

### Reload Configuration

```bash
# Method 1: SQL
SELECT pg_reload_conf();

# Method 2: Command line
pg_ctl reload -D /path/to/data

# Method 3: System service
sudo systemctl reload postgresql
```

## Multi-Database Setup

Each database needs its own worker:

```sql
-- Database 1
\c database1
SELECT ttl_start_worker();
SELECT ttl_create_index('sessions', 'created_at', 3600);

-- Database 2
\c database2
SELECT ttl_start_worker();
SELECT ttl_create_index('logs', 'logged_at', 604800);
```

## Production Configuration Examples

### High-Traffic Web Application

```sql
-- Aggressive cleanup for sessions
SELECT ttl_create_index('user_sessions', 'last_activity', 900, 25000);  -- 15 min

-- Moderate cleanup for logs
SELECT ttl_create_index('access_logs', 'timestamp', 86400, 50000);  -- 1 day

-- Long retention for audit
SELECT ttl_create_index('audit_log', 'created_at', 2592000, 10000);  -- 30 days

-- Worker runs every 30 seconds
ALTER SYSTEM SET pg_ttl_index.naptime = 30;
SELECT pg_reload_conf();
```

### Analytics Platform

```sql
-- Short-term raw events
SELECT ttl_create_index('raw_events', 'timestamp', 3600, 100000);  -- 1 hour

-- Medium-term aggregated data
SELECT ttl_create_index('hourly_stats', 'hour', 604800, 10000);  -- 7 days

-- Long-term summaries
SELECT ttl_create_index('daily_stats', 'day', 7776000, 1000);  -- 90 days

-- Less frequent cleanup (lower overhead)
ALTER SYSTEM SET pg_ttl_index.naptime = 120;  -- 2 minutes
SELECT pg_reload_conf();
```

### Development Environment

```sql
-- Fast cleanup for testing
SELECT ttl_create_index('test_data', 'created_at', 60, 1000);  -- 1 minute!

-- Frequent runs for quick feedback
ALTER SYSTEM SET pg_ttl_index.naptime = 10;  -- 10 seconds
SELECT pg_reload_conf();
```

## Best Practices

### 1. Match Expiry to Data Lifecycle

```sql
-- Session data: match session timeout
SELECT ttl_create_index('sessions', 'created_at', 1800);  -- 30 min

-- Cache: match cache strategy
SELECT ttl_create_index('cache', 'expires_at', 0);  -- Immediate

-- Logs: match retention policy
SELECT ttl_create_index('logs', 'timestamp', 604800);  -- 7 days
```

### 2. Size Batch to Peak Load

```sql
-- If you insert 100K rows/hour and cleanup runs every 60 seconds:
-- Expected deletions per run ≈ 100K / 60 ≈ 1,666 rows
-- Set batch size to 2-3x that: 5,000
SELECT ttl_create_index('high_volume_table', 'created_at', 3600, 5000);
```

### 3. Monitor and Adjust

```sql
-- Check actual deletion rates
SELECT 
    table_name,
    rows_deleted_last_run,
    batch_size,
    CASE 
        WHEN rows_deleted_last_run >= batch_size 
        THEN 'Consider increasing batch_size'
        ELSE 'OK'
    END AS recommendation
FROM ttl_summary();
```

### 4. Use Maintenance Windows

```sql
-- Disable during high-load periods
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();

-- Re-enable during low traffic
ALTER SYSTEM SET pg_ttl_index.enabled = true;
SELECT pg_reload_conf();
```

## Troubleshooting Configuration

### Worker Not Respecting naptime

```sql
-- Verify setting
SHOW pg_ttl_index.naptime;

-- Restart worker to pick up changes
SELECT ttl_stop_worker();
SELECT ttl_start_worker();
```

### Changes Not Taking Effect

```sql
-- Reload configuration
SELECT pg_reload_conf();

-- Verify change
SHOW pg_ttl_index.naptime;
SHOW pg_ttl_index.enabled;
```

### Cleanup Running Too Often

```sql
-- Increase naptime
ALTER SYSTEM SET pg_ttl_index.naptime = 300;  -- 5 minutes
SELECT pg_reload_conf();
```

## See Also

- [API Configuration](../api/configuration.md) - Parameter reference
- [Performance Tuning](../advanced/performance.md) - Optimization strategies
- [Monitoring](monitoring.md) - Track configuration effectiveness
