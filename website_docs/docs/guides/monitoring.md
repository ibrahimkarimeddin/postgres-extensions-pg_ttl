---
sidebar_position: 3
---

# Monitoring Guide

Track and monitor TTL cleanup activity for optimal performance.

## Quick Status Check

```sql
-- One-stop monitoring query
SELECT 
    table_name,
    active,
    expire_after_seconds / 3600.0 AS expire_hours,
    last_run,
    time_since_last_run,
    rows_deleted_last_run,
    total_rows_deleted
FROM ttl_summary()
ORDER BY table_name;
```

## Worker Health Monitoring

### Check Worker Status

```sql
-- Is the worker running?
SELECT * FROM ttl_worker_status();
```

Expected output when healthy:
```
worker_pid | application_name  | state | backend_start       | database_name
-----------+-------------------+-------+---------------------+---------------
    12345  | TTL Worker DB... | idle  | 2026-01-03 02:00... | mydb
```

### Worker Uptime

```sql
SELECT 
    worker_pid,
    NOW() - backend_start AS uptime,
    state
FROM ttl_worker_status();
```

### Detect Missing Worker

```sql
-- Alert if no worker running
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ttl_worker_status()) THEN
        RAISE WARNING 'TTL worker is not running!';
    END IF;
END $$;
```

## Cleanup Activity Monitoring

### Recent Cleanup Activity

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

### Tables with Overdue Cleanup

```sql
-- Find tables where cleanup hasn't run recently
SELECT 
    table_name,
    time_since_last_run,
    active
FROM ttl_summary()
WHERE active = true
  AND (last_run IS NULL OR last_run < NOW() - INTERVAL '5 minutes')
ORDER BY last_run NULLS FIRST;
```

### High-Volume Deletion Tracking

```sql
SELECT 
    table_name,
    rows_deleted_last_run,
    total_rows_deleted,
    last_run
FROM ttl_summary()
WHERE rows_deleted_last_run > 10000
ORDER BY rows_deleted_last_run DESC;
```

## Performance Monitoring

### Deletion Rate Analysis

```sql
SELECT 
    table_name,
    rows_deleted_last_run,
    batch_size,
    CASE 
        WHEN rows_deleted_last_run >= batch_size 
        THEN 'May need larger batch'
        WHEN rows_deleted_last_run < batch_size * 0.1 
        THEN 'Batch size OK'
        ELSE 'Optimal'
    END AS batch_assessment
FROM ttl_summary()
WHERE active = true;
```

### Average Deletion Per Day

```sql
SELECT 
    table_name,
    total_rows_deleted,
    EXTRACT(EPOCH FROM (NOW() -created_at)) / 86400 AS days_active,
    ROUND(total_rows_deleted / NULLIF(EXTRACT(EPOCH FROM (NOW() - created_at)) / 86400, 0)) AS avg_per_day
FROM ttl_index_table
WHERE created_at < NOW() - INTERVAL '1 day';
```

## Alerting Queries

### Critical: Worker Down

```sql
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN 'CRITICAL: TTL worker not running'
        ELSE 'OK: Worker running'
    END AS status
FROM ttl_worker_status();
```

### Warning: Cleanup Lag

```sql
SELECT 
    table_name,
    time_since_last_run
FROM ttl_summary()
WHERE active = true
  AND time_since_last_run > INTERVAL '10 minutes'
ORDER BY time_since_last_run DESC;
```

### Info: High Deletion Rate

```sql
SELECT 
    table_name,
    rows_deleted_last_run
FROM ttl_summary()
WHERE rows_deleted_last_run > 50000;
```

## Dashboard Queries

### Summary Dashboard

```sql
SELECT 
    COUNT(*) FILTER (WHERE active = true) AS active_ttl_indexes,
    COUNT(*) AS total_ttl_indexes,
    SUM(total_rows_deleted) AS total_deletions,
    MAX(last_run) AS most_recent_cleanup
FROM ttl_index_table;
```

### Per-Table Dashboard

```sql
SELECT 
    table_name,
    expire_after_seconds || 's' AS ttl,
    CASE WHEN active THEN '✓' ELSE '✗' END AS active,
    COALESCE(rows_deleted_last_run::TEXT, '-') AS last_run_deletions,
    COALESCE(time_since_last_run::TEXT, 'Never') AS last_cleanup
FROM ttl_summary()
ORDER BY table_name;
```

## Integration with Monitoring Tools

### Prometheus/Grafana Metrics

Create a view for metrics export:

```sql
CREATE OR REPLACE VIEW ttl_metrics AS
SELECT 
    table_name AS table,
    expire_after_seconds,
    CASE WHEN active THEN 1 ELSE 0 END AS is_active,
    COALESCE(rows_deleted_last_run, 0) AS rows_deleted_last,
    COALESCE(total_rows_deleted, 0) AS rows_deleted_total,
    EXTRACT(EPOCH FROM COALESCE(time_since_last_run, INTERVAL '0')) AS seconds_since_last_run
FROM ttl_summary();
```

### Datadog/New Relic Integration

```sql
-- Export TTL statistics as JSON
SELECT json_agg(json_build_object(
    'table', table_name,
    'active', active,
    'rows_deleted_last_run', rows_deleted_last_run,
    'total_rows_deleted', total_rows_deleted,
    'last_run_timestamp', EXTRACT(EPOCH FROM last_run)
)) AS ttl_stats
FROM ttl_summary();
```

## Logging and Audit

### Enable Detailed Logging

```sql
-- Enable debug logging
ALTER SYSTEM SET log_min_messages = 'debug1';
SELECT pg_reload_conf();

-- Check PostgreSQL logs
-- tail -f /var/log/postgresql/postgresql-*.log | grep TTL
```

### Track Configuration Changes

```sql
-- View current vs default configuration
SELECT 
    name,
    setting AS current_value,
    boot_val AS default_value,
    source
FROM pg_settings
WHERE name LIKE 'pg_ttl_index%';
```

## Automated Monitoring Scripts

### Daily Health Check (SQL)

```sql
-- Save as daily_ttl_check.sql
DO $$
DECLARE
    worker_count INTEGER;
    stale_count INTEGER;
BEGIN
    -- Check worker
    SELECT COUNT(*) INTO worker_count FROM ttl_worker_status();
    IF worker_count = 0 THEN
        RAISE WARNING 'TTL worker is not running';
    END IF;
    
    -- Check stale cleanups
    SELECT COUNT(*) INTO stale_count
    FROM ttl_summary()
    WHERE active = true
      AND time_since_last_run > INTERVAL '10 minutes';
    
    IF stale_count > 0 THEN
        RAISE WARNING '% tables have stale cleanups', stale_count;
    END IF;
    
    RAISE NOTICE 'Health check complete. Worker: %, Stale tables: %', 
                 worker_count, stale_count;
END $$;
```

### Monitoring Functions

```sql
-- Create custom monitoring function
CREATE OR REPLACE FUNCTION ttl_health_check()
RETURNS TABLE(
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
BEGIN
    -- Worker status
    RETURN QUERY
    SELECT 
        'Worker Status'::TEXT,
        CASE WHEN EXISTS(SELECT 1 FROM ttl_worker_status())
             THEN 'OK' ELSE 'FAIL' END,
        COALESCE((SELECT COUNT(*)::TEXT FROM ttl_worker_status()), '0') || ' workers';
    
    -- Active tables
    RETURN QUERY
    SELECT 
        'Active TTL Tables'::TEXT,
        'INFO'::TEXT,
        COUNT(*)::TEXT || ' tables'
    FROM ttl_index_table
    WHERE active = true;
    
    -- Stale cleanups
    RETURN QUERY
    SELECT 
        'Stale Cleanups'::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'WARN' END,
        COUNT(*)::TEXT || ' tables'
    FROM ttl_summary()
    WHERE active = true
      AND time_since_last_run > INTERVAL '10 minutes';
END;
$$ LANGUAGE plpgsql;

-- Use it
SELECT * FROM ttl_health_check();
```

## Best Practices

1. **Monitor worker uptime** - Restart after PostgreSQL restarts
2. **Check cleanup lag** - Ensure cleanup runs regularly
3. **Track deletion rates** - Adjust batch sizes accordingly
4. **Log configuration changes** - Document TTL modifications
5. **Set up alerts** - Proactive issue detection

## See Also

- [Configuration Guide](configuration.md) - Tuning parameters
- [Troubleshooting](../advanced/troubleshooting.md) - Common issues
- [API Reference](../api/functions.md) - Monitoring functions
