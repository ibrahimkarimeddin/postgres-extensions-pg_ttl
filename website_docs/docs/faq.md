---
sidebar_position: 1
---

# Frequently Asked Questions

Common questions about `pg_ttl_index`.

## General Questions

### What is pg_ttl_index?

A PostgreSQL extension that automatically deletes expired data based on timestamp columns. Think of it as "auto-expire" for your database tables.

### How is this different from just running DELETE queries?

- **Automatic**: No manual queries or cron jobs needed
- **Optimized**: Batch deletions with advisory locks
- **Safe**: Per-table error handling, ACID compliant
- **Monitored**: Built-in statistics tracking

### Which PostgreSQL versions are supported?

PostgreSQL 12.0 and higher.

### Is it production-ready?

Yes! Version 2.0.0 includes:
- Batch deletion for high-load scenarios
- Concurrency control via advisory locks
- Per-table error handling
- Comprehensive stats tracking

## Installation & Setup

### Do I need to restart PostgreSQL?

Yes, when:
- First installing (to load shared library)
- Updating to new version (shared library changes)

No, when:
- Changing configuration parameters (just reload)
- Creating/dropping TTL indexes

### Does the background worker start automatically?

**No**. You must manually start it after installing:

```sql
SELECT ttl_start_worker();
```

### Do I need superuser privileges?

- **Installation**: Yes (CREATE EXTENSION requires superuser)
- **Daily usage**: No (grant permissions to regular users)

### Can I use it on a read replica?

No. TTL requires write access to delete rows. Only run on primary.

## Configuration

### How often does cleanup run?

Default: Every 60 seconds (`pg_ttl_index.naptime`)

Configurable:
```sql
ALTER SYSTEM SET pg_ttl_index.naptime = 30;  -- 30 seconds
```

### What's an appropriate batch size?

**Rule of thumb**: 2-3x your expected deletions per cleanup run

| Expected Deletions/Run | Batch Size |
|------------------------|------------|
| < 1,000 | 1,000 - 5,000 |
| 1,000 - 10,000 | 10,000 (default) |
| 10,000 - 50,000 | 25,000 - 50,000 |
| > 50,000 | 50,000 - 100,000 |

### Can I have different TTLs for different tables?

Yes! Each table can have its own expiration time:

```sql
SELECT ttl_create_index('sessions', 'created_at', 1800);    -- 30 min
SELECT ttl_create_index('logs', 'logged_at', 604800);       -- 7 days
```

### Can I have multiple TTL columns per table?

Yes, but it's not common:

```sql
SELECT ttl_create_index('table', 'created_at', 3600);
SELECT ttl_create_index('table', 'expires_at', 0);
-- Both will be checked and enforced
```

## Performance

### Will TTL impact my database performance?

**Minimal impact** when properly configured:
- Runs in small batches (reduces locking)
- Sleeps between batches (yields to other queries)
- Uses efficient ctid-based deletion

**Monitor and tune** if needed:
- Adjust batch size
- Change cleanup frequency (naptime)
- Schedule during off-peak hours

### How do I know if cleanup is keeping up?

```sql
SELECT 
    table_name,
    rows_deleted_last_run,
    batch_size,
    CASE 
        WHEN rows_deleted_last_run >= batch_size 
        THEN 'Consider increasing batch_size'
        ELSE 'Keeping up'
    END AS status
FROM ttl_summary();
```

### What if I have millions of expired rows?

Increase batch size:

```sql
SELECT ttl_create_index('huge_table', 'timestamp', 3600, 100000);
```

Or temporarily disable automatic cleanup and run manual cleanup:

```sql
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();

-- Manual cleanup during maintenance window
SELECT ttl_runner();

-- Re-enable
ALTER SYSTEM SET pg_ttl_index.enabled = true;
SELECT pg_reload_conf();
```

## Troubleshooting

### Why isn't data being deleted?

Check these in order:

1. **Worker running?**
```sql
SELECT * FROM ttl_worker_status();
```

2. **TTL active?**
```sql
SELECT active FROM ttl_index_table WHERE table_name = 'your_table';
```

3. **Data actually expired?**
```sql
SELECT COUNT(*) FROM your_table 
WHERE created_at < NOW() - INTERVAL '1 hour';
```

4. **Manually trigger cleanup:**
```sql
SELECT ttl_runner();
```

### Worker stopped after PostgreSQL restart - why?

This is expected behavior. Restart it manually:

```sql
SELECT ttl_start_worker();
```

**Workaround**: Add to database startup script or use cron:

```bash
@reboot psql -d your_db -c "SELECT ttl_start_worker();"
```

### How do I check if TTL is working?

```sql
-- Check cleanup activity
SELECT * FROM ttl_summary();

-- Should show last_run, rows_deleted stats
```

## Data Management

### Can I disable TTL temporarily?

Yes, multiple ways:

**Per table**:
```sql
UPDATE ttl_index_table SET active = false WHERE table_name = 'my_table';
```

**Globally**:
```sql
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();
```

**Stop worker**:
```sql
SELECT ttl_stop_worker();
```

### What happens to data that's about to expire if I disable TTL?

Nothing - it stays in the table. Data is only deleted when:
1. Worker is running
2. TTL is active
3. Table's TTL is active

### Can I preview what will be deleted?

Yes:

```sql
-- See what would be deleted
SELECT COUNT(*), MIN(created_at), MAX(created_at)
FROM your_table
WHERE created_at < NOW() - INTERVAL '1 hour';
```

### Does TTL work with table partitions?

Yes! Apply TTL to the parent table:

```sql
-- Parent table
CREATE TABLE logs (...) PARTITION BY RANGE (created_at);

-- TTL on parent handles all partitions
SELECT ttl_create_index('logs', 'created_at', 604800);
```

## Advanced Usage

### Can I archive data before TTL deletes it?

Yes, set up archival before expiration:

```sql
-- TTL deletes after 7 days
SELECT ttl_create_index('logs', 'created_at', 604800);

-- Archive data > 6 days old (before TTL kicks in)
-- Run this as a cron job or scheduled task
INSERT INTO logs_archive
SELECT * FROM logs
WHERE created_at < NOW() - INTERVAL '6 days';
```

### Can I use TTL with unlogged tables?

Yes, but be careful - unlogged tables lose data on crash:

```sql
CREATE UNLOGGED TABLE temp_cache (...);
SELECT ttl_create_index('temp_cache', 'created_at', 300);
```

### How do I monitor TTL in production?

1. **Worker health**:
```sql
SELECT COUNT(*) FROM ttl_worker_status();
```

2. **Cleanup effectiveness**:
```sql
SELECT * FROM ttl_summary();
```

3. **Integration** with monitoring tools (Datadog, Prometheus):
```sql
CREATE VIEW ttl_metrics AS
SELECT table_name, total_rows_deleted, rows_deleted_last_run
FROM ttl_summary();
```

## Comparison with Alternatives

### vs. PostgreSQL table partitioning with DROP?

**pg_ttl_index**:
- ✅ Row-level granularity
- ✅ Change TTL anytime
- ❌ Slower for very large deletions

**Partitioning**:
- ✅ Very fast (DROP partition)
- ❌ Partition-level granularity
- ❌ Schema changes required

**Use both** for best results: partition + TTL on each partition.

### vs. cron job with DELETE?

**pg_ttl_index**:
- ✅ Native PostgreSQL integration
- ✅ Built-in monitoring
- ✅ Automatic batch sizing

**Cron**:
- ❌ External dependency
- ❌ Manual coordination
- ❌ Custom monitoring needed

### vs. application-level cleanup?

**pg_ttl_index**:
- ✅ Centralized in database
- ✅ Works across all apps
- ✅ Guaranteed execution

**Application**:
- ❌ Scattered across codebase
- ❌ Per-application overhead
- ❌ May not run if app crashes

## Getting Help

### Where can I report bugs?

[GitHub Issues](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/issues)

### Where's the source code?

[GitHub Repository](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl)

### How do I contribute?

See our [Contributing Guide](contributing.md)!

### Can I get commercial support?

Open source project - community support via GitHub Issues and Discussions.

## Still Have Questions?

Check our comprehensive documentation:

- [Installation Guide](installation.md)
- [Quick Start](quick-start.md)
- [API Reference](api/functions.md)
- [Troubleshooting](advanced/troubleshooting.md)
