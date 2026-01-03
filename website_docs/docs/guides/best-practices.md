---
sidebar_position: 4
---

# Best Practices

Production-tested recommendations for using `pg_ttl_index` effectively.

## Choosing Expiration Times

###Match Business Requirements

```sql
-- Session timeout: match application session duration
SELECT ttl_create_index('sessions', 'last_activity', 1800);  -- 30 min

-- Legal/compliance: match retention requirements
SELECT ttl_create_index('audit_log', 'created_at', 7776000);  -- 90 days

-- Cache: match cache invalidation strategy
SELECT ttl_create_index('cache', 'expires_at', 0);  -- Immediate
```

### Common Expiration Periods

| Use Case | Recommended TTL | Seconds |
|----------|----------------|---------|
| User sessions | 15-60 minutes | 900-3600 |
| API rate limiting | 1-60 minutes | 60-3600 |
| Cache entries | 5-60 minutes | 300-3600 |
| Application logs | 7-30 days | 604800-2592000 |
| Audit trails | 90-365 days | 7776000-31536000 |
| Metrics (raw) | 1-24 hours | 3600-86400 |
| Temporary data | 1-24 hours | 3600-86400 |

## Batch Size Optimization

### Size Based on Volume

```sql
-- Low volume (< 1K deletions/hour)
SELECT ttl_create_index('notifications', 'created_at', 86400, 1000);

-- Medium volume (1K-10K deletions/hour)
SELECT ttl_create_index('sessions', 'created_at', 3600, 10000);

-- High volume (10K-100K deletions/hour)
SELECT ttl_create_index('events', 'timestamp', 3600, 50000);

-- Very high volume (> 100K deletions/hour)
SELECT ttl_create_index('metrics', 'collected_at', 3600, 100000);
```

### Monitor and Adjust

```sql
-- Check if batch size is adequate
SELECT 
    table_name,
    batch_size,
    rows_deleted_last_run,
    CASE 
        WHEN rows_deleted_last_run >= batch_size 
        THEN 'Increase batch_size'
        WHEN rows_deleted_last_run < batch_size * 0.1
        THEN 'Decrease batch_size'
        ELSE 'Optimal'
    END AS recommendation
FROM ttl_summary();
```

## Index Strategy

### Trust Auto-Indexing

The extension creates indexes automatically:

```sql
-- This creates idx_ttl_sessions_created_at automatically
SELECT ttl_create_index('sessions', 'created_at', 3600);
```

### Composite Indexes for Queries

If you query on TTL column + others, create composite index:

```sql
-- Application queries often filter by user_id AND created_at
CREATE INDEX idx_sessions_user_created ON sessions(user_id, created_at);

-- TTL still uses its auto-created index for cleanup
SELECT ttl_create_index('sessions', 'created_at', 3600);
```

### Partitioning with TTL

For very large tables, combine partitioning with TTL:

```sql
-- Partition by month
CREATE TABLE logs (
    id BIGSERIAL,
    message TEXT,
    logged_at TIMESTAMPTZ NOT NULL
) PARTITION BY RANGE (logged_at);

-- Create partitions
CREATE TABLE logs_2026_01 PARTITION OF logs
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

-- TTL on parent table handles all partitions
SELECT ttl_create_index('logs', 'logged_at', 2592000, 50000);
```

## Performance Optimization

### Off-Peak Cleanup

Schedule intensive cleanup during low-traffic periods:

```sql
-- Disable during peak hours (example)
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();

-- Re-enable during off-peak
ALTER SYSTEM SET pg_ttl_index.enabled = true;
SELECT pg_reload_conf();
```

### Tune Cleanup Interval

```sql
-- High-priority cleanup: shorter interval
ALTER SYSTEM SET pg_ttl_index.naptime = 30;  -- 30 seconds

-- Low-priority cleanup: longer interval  
ALTER SYSTEM SET pg_ttl_index.naptime = 300;  -- 5 minutes

SELECT pg_reload_conf();
```

### Monitor System Impact

```sql
-- Check if cleanup is causing load
SELECT 
    table_name,
    rows_deleted_last_run,
    batch_size
FROM ttl_summary()
WHERE rows_deleted_last_run > 100000;  -- Flag high-volume deletions
```

## Data Retention Strategy

### Tiered Retention

```sql
-- Hot data: 1 day (fast queries, frequent access)
SELECT ttl_create_index('events_hot', 'timestamp', 86400, 50000);

-- Warm data: 7 days (analytics, occasional access)
SELECT ttl_create_index('events_warm', 'timestamp', 604800, 25000);

-- Cold data: 90 days (compliance, rare access)
SELECT ttl_create_index('events_cold', 'timestamp', 7776000, 10000);
```

### Archive Before Delete

```sql
-- Archive old data before TTL deletes it
CREATE TABLE logs_archive (LIKE logs INCLUDING ALL);

-- Archival process (run before TTL kicks in)
INSERT INTO logs_archive
SELECT * FROM logs
WHERE logged_at < NOW() - INTERVAL '6 days';

-- TTL cleans up after 7 days
SELECT ttl_create_index('logs', 'logged_at', 604800);
```

## Error Handling

### Per-Table Isolation

TTL errors in one table don't affect others:

```sql
-- Even if table1 fails, table2 continues to clean up
SELECT ttl_create_index('table1', 'created_at', 3600);
SELECT ttl_create_index('table2', 'created_at', 3600);
```

### Monitor Warnings

```sql
-- Check PostgreSQL logs for TTL warnings
-- tail -f /var/log/postgresql/postgresql-*.log | grep TTL
```

## High Availability

### Worker Management

```sql
-- After database restart, restart worker
SELECT ttl_start_worker();

-- Verify worker is running
SELECT * FROM ttl_worker_status();
```

### Monitoring Integration

```sql
-- Create monitoring view
CREATE OR REPLACE VIEW ttl_health AS
SELECT 
    (SELECT COUNT(*) FROM ttl_worker_status()) AS worker_count,
    (SELECT COUNT(*) FROM ttl_summary() WHERE active = true) AS active_tables,
    (SELECT SUM(total_rows_deleted) FROM ttl_summary()) AS total_deletions;

-- Alert if worker down
SELECT * FROM ttl_health WHERE worker_count = 0;
```

## Security

### Permissions

```sql
-- Grant TTL management to specific role
GRANT USAGE ON SCHEMA public TO ttl_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ttl_index_table TO ttl_admin;
GRANT EXECUTE ON FUNCTION ttl_create_index TO ttl_admin;
GRANT EXECUTE ON FUNCTION ttl_drop_index TO ttl_admin;
```

### Audit TTL Changes

```sql
-- Track who modifies TTL configuration
CREATE TABLE ttl_audit (
    id SERIAL PRIMARY KEY,
    username TEXT DEFAULT current_user,
    action TEXT,
    table_name TEXT,
    old_value JSONB,
    new_value JSONB,
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Trigger to log changes (example)
```

## Testing

### Development Environment

```sql
-- Fast TTL for testing
SELECT ttl_create_index('test_table', 'created_at', 60, 100);  -- 1 minute

-- Frequent cleanup
ALTER SYSTEM SET pg_ttl_index.naptime = 10;  -- 10 seconds
SELECT pg_reload_conf();
```

### Validate TTL Behavior

```sql
-- Insert test data
INSERT INTO test_table (data, created_at)
VALUES ('old', NOW() - INTERVAL '2 minutes'),
       ('new', NOW());

-- Wait > naptime, then check
SELECT COUNT(*) FROM test_table;  -- Should only show recent data
```

## Maintenance

### Regular Health Checks

```sql
-- Weekly review
SELECT 
    table_name,
    total_rows_deleted,
    last_run,
    active
FROM ttl_summary()
ORDER BY total_rows_deleted DESC;
```

### Configuration Backup

```sql
-- Export TTL configuration
COPY ttl_index_table TO '/backup/ttl_config.csv' CSV HEADER;

-- Restore if needed
COPY ttl_index_table FROM '/backup/ttl_config.csv' CSV HEADER;
```

## Common Anti-Patterns

### ❌ Don't: Set TTL < Cleanup Interval

```sql
-- BAD: TTL 30 seconds, naptime 60 seconds
SELECT ttl_create_index('table', 'created_at', 30);
-- Sets naptime to 60 seconds (default)

-- Data will sit for up to 90 seconds (30 + 60)
```

✅ **Do**: Ensure TTL > naptime for timely cleanup

```sql
-- GOOD
SELECT ttl_create_index('table', 'created_at', 300);  -- 5 minutes
ALTER SYSTEM SET pg_ttl_index.naptime = 60;  -- 1 minute
```

### ❌ Don't: Forget to Start Worker

```sql
-- BAD: Create TTL but forget to start worker
SELECT ttl_create_index('table', 'created_at', 3600);
-- Nothing happens!
```

✅ **Do**: Always start the worker

```sql
-- GOOD
SELECT ttl_start_worker();
SELECT ttl_create_index('table', 'created_at', 3600);
```

### ❌ Don't: Use Tiny Batch Sizes

```sql
-- BAD: Batch size too small for large table
SELECT ttl_create_index('huge_table', 'created_at', 3600, 10);
-- Will take forever to clean up
```

✅ **Do**: Size batches appropriately

```sql
-- GOOD: Match batch size to volume
SELECT ttl_create_index('huge_table', 'created_at', 3600, 50000);
```

## Production Checklist

- [ ] Worker started in each database
- [ ] TTL times match business requirements
- [ ] Batch sizes optimized for volume
- [ ] Monitoring in place (worker health, cleanup lag)
- [ ] Alerts configured for worker down/cleanup failures
- [ ] Configuration backed up
- [ ] Tested in staging first
- [ ] Documentation updated with TTL policies

## See Also

- [Performance Guide](../advanced/performance.md) - Detailed optimization
- [Monitoring Guide](monitoring.md) - Track effectiveness
- [Configuration Guide](configuration.md) - Tuning options
