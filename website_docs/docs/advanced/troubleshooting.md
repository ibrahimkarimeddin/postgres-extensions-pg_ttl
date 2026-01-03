---
sidebar_position: 3
---

# Troubleshooting Guide

Solutions to common problems and error messages.

## Extension Installation Issues

### Extension Files Not Found

**Error**: `ERROR: could not open extension control file`

**Cause**: Extension files not properly installed

**Solution**:
```bash
# Verify installation
ls -la $(pg_config --sharedir)/extension/pg_ttl_index*

# Reinstall if missing
sudo make install

# Or via PGXN
pgxn install pg_ttl_index
```

### Shared Library Not Loading

**Error**: `ERROR: could not load library`

**Cause**: Extension not in `shared_preload_libraries`

**Solution**:
```bash
# Edit postgresql.conf
sudo nano /etc/postgresql/16/main/postgresql.conf

# Add this line:
shared_preload_libraries = 'pg_ttl_index'

# Restart PostgreSQL (required!)
sudo systemctl restart postgresql
```

**Verification**:
```sql
SHOW shared_preload_libraries;
-- Should include 'pg_ttl_index'
```

## Background Worker Issues

### Worker Not Starting

**Error**: `ttl_worker_status()` returns no rows

**Solution 1**: Start the worker manually
```sql
SELECT ttl_start_worker();
```

**Solution 2**: Check if enabled
```sql
SHOW pg_ttl_index.enabled;

-- If false, enable it
ALTER SYSTEM SET pg_ttl_index.enabled = true;
SELECT pg_reload_conf();
```

**Solution 3**: Verify extension loaded
```sql
\dx pg_ttl_index
-- Should show version 2.0.0
```

### Worker Crashes Immediately

**Check logs**:
```bash
sudo tail -f /var/log/postgresql/postgresql-*.log | grep -i "ttl\|error"
```

**Common causes**:
- Permission issues
- Database doesn't exist
- Extension not properly initialized

### Worker Stops After PostgreSQL Restart

**This is normal behavior**.  Worker doesn't auto-start.

**Solution**: Add to database startup script
```sql
-- Run after every PostgreSQL restart
SELECT ttl_start_worker();
```

**Automate with cron** (example):
```bash
# /etc/cron.d/ttl-worker
@reboot postgres psql -d your_database -c "SELECT ttl_start_worker();"
```

## Cleanup Not Working

### Data Not Being Deleted

**Diagnosis**:
```sql
-- 1. Check worker status
SELECT * FROM ttl_worker_status();

-- 2. Check TTL configuration
SELECT * FROM ttl_summary();

-- 3. Check if TTL is active
SELECT active FROM ttl_index_table 
WHERE table_name = 'your_table';
```

**Solutions**:

**If worker not running**:
```sql
SELECT ttl_start_worker();
```

**If TTL inactive**:
```sql
UPDATE ttl_index_table 
SET active = true 
WHERE table_name = 'your_table';
```

**If cleanup hasn't run recently**:
```sql
-- Manually trigger
SELECT ttl_runner();
```

### Wrong Column Being Used

**Error**: Cleanup doesn't work as expected

**Diagnosis**:
```sql
-- Check which column is configured
SELECT table_name, column_name, expire_after_seconds
FROM ttl_index_table
WHERE table_name = 'your_table';
```

**Solution**: Recreate with correct column
```sql
-- Drop old TTL
SELECT ttl_drop_index('your_table', 'wrong_column');

-- Create with correct column
SELECT ttl_create_index('your_table', 'correct_column', 3600);
```

### Cleanup Runs But Doesn't Delete

**Check for expired data**:
```sql
SELECT COUNT(*)
FROM your_table
WHERE created_at < NOW() - INTERVAL '1 hour';
-- Should match expected deletions
```

**Check timestamp column**:
```sql
-- Verify column data type
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'your_table'
  AND column_name = 'created_at';
-- Must be timestamp, timestamptz, or date
```

## Permission Errors

### Permission Denied to Create Extension

**Error**: `ERROR: permission denied to create extension`

**Solution**: Need superuser privileges
```sql
-- As superuser
\c your_database postgres

CREATE EXTENSION pg_ttl_index;

-- Or grant superuser temporarily
ALTER USER your_user SUPERUSER;
-- Create extension
ALTER USER your_user NOSUPERUSER;
```

### Permission Denied on ttl_index_table

**Error**: `ERROR: permission denied for table ttl_index_table`

**Solution**: Grant necessary permissions
```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON ttl_index_table TO your_user;
GRANT EXECUTE ON FUNCTION ttl_create_index TO your_user;
GRANT EXECUTE ON FUNCTION ttl_drop_index TO your_user;
GRANT EXECUTE ON FUNCTION ttl_runner TO your_user;
```

## Configuration Issues

### Settings Not Taking Effect

**Diagnosis**:
```sql
-- Check current settings
SHOW pg_ttl_index.naptime;
SHOW pg_ttl_index.enabled;

-- Check configuration source
SELECT name, setting, source
FROM pg_settings
WHERE name LIKE 'pg_ttl_index%';
```

**Solution**: Reload configuration
```sql
-- Reload PostgreSQL config
SELECT pg_reload_conf();

-- Restart worker to pick up changes
SELECT ttl_stop_worker();
SELECT ttl_start_worker();
```

### Can't Set Configuration Parameter

**Error**: `ERROR: unrecognized configuration parameter`

**Cause**: Extension not in `shared_preload_libraries`

**Solution**:
```bash
# Edit postgresql.conf
shared_preload_libraries = 'pg_ttl_index'

# Restart PostgreSQL
sudo systemctl restart postgresql
```

## Performance Issues

### Cleanup Takes Too Long

**Diagnosis**:
```sql
-- Check deletion volumes
SELECT 
    table_name,
    rows_deleted_last_run,
    batch_size
FROM ttl_summary()
ORDER BY rows_deleted_last_run DESC;
```

**Solutions**:

**Increase batch size**:
```sql
UPDATE ttl_index_table
SET batch_size = 50000
WHERE table_name = 'high_volume_table';
```

**Verify index exists**:
```sql
SELECT index_name
FROM ttl_index_table
WHERE table_name = 'your_table';

-- Verify index is actually there
\di+ idx_ttl_your_table_*
```

**Run VACUUM**:
```sql
VACUUM ANALYZE your_table;
```

### High CPU Usage

**Diagnosis**:
```sql
-- Check cleanup frequency
SHOW pg_ttl_index.naptime;

-- Check recent activity
SELECT * FROM pg_stat_activity
WHERE application_name LIKE 'TTL Worker%';
```

**Solutions**:

**Reduce cleanup frequency**:
```sql
ALTER SYSTEM SET pg_ttl_index.naptime = 300;  -- 5 minutes
SELECT pg_reload_conf();
```

**Smaller batch sizes**:
```sql
UPDATE ttl_index_table
SET batch_size = 5000
WHERE table_name = 'your_table';
```

### Table Bloat

**Diagnosis**:
```sql
-- Check table size
SELECT pg_size_pretty(pg_total_relation_size('your_table'));

-- Check bloat (requires pgstattuple extension)
CREATE EXTENSION IF NOT EXISTS pgstattuple;
SELECT * FROM pgstattuple('your_table');
```

**Solution**:
```sql
-- More aggressive autovacuum
ALTER TABLE your_table SET (
    autovacuum_vacuum_scale_factor = 0.05
);

-- Manual vacuum (doesn't lock table)
VACUUM ANALYZE your_table;

-- Full vacuum (locks table - use with caution!)
VACUUM FULL your_table;
```

## Error Messages

### "Another instance is already running"

**Message**: `NOTICE: TTL runner: Another instance is already running, skipping`

**This is normal**: Advisory lock prevents overlapping runs

**Action**: No action needed unless it happens frequently

**If frequent**:
- Increase batch size (cleanup finishes faster)
- Increase naptime (runs less often)

### "Column must be a date/timestamp type"

**Error**: During `ttl_create_index()`

**Cause**: Specified column is not a timestamp type

**Solution**:
```sql
-- Check column type
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'your_table'
  AND column_name = 'your_column';

-- Must be one of: timestamp, timestamptz, date
```

**Fix**: Use correct column or change column type
```sql
-- Change column type
ALTER TABLE your_table 
ALTER COLUMN your_column TYPE TIMESTAMPTZ;

-- Then create TTL
SELECT ttl_create_index('your_table', 'your_column', 3600);
```

### "Failed to cleanup table"

**Warning**: In PostgreSQL logs

**Cause**: Error during cleanup (e.g., table dropped, column changed)

**Diagnosis**:
```bash
# Check logs for full error
sudo tail -f /var/log/postgresql/postgresql-*.log | grep -A 5 "Failed to cleanup"
```

**Solution**: Fix the underlying issue or drop TTL
```sql
-- If table no longer exists
SELECT ttl_drop_index('old_table', 'created_at');

-- If column was renamed
SELECT ttl_drop_index('table', 'old_column');
SELECT ttl_create_index('table', 'new_column', 3600);
```

## Debugging Tips

### Enable Debug Logging

```sql
-- Enable detailed logging
ALTER SYSTEM SET log_min_messages = 'debug1';
ALTER SYSTEM SET log_error_verbosity = 'verbose';
SELECT pg_reload_conf();

-- Watch logs
-- tail -f /var/log/postgresql/postgresql-*.log
```

### Manual Testing

```sql
-- Test cleanup manually
SELECT ttl_runner();

-- Check what would be deleted (doesn't actually delete)
SELECT COUNT(*)
FROM your_table
WHERE created_at < NOW() - INTERVAL '1 hour';
```

### Check Extension Version

```sql
-- Verify extension version
SELECT * FROM pg_available_extensions 
WHERE name = 'pg_ttl_index';

-- Check installed version
\dx pg_ttl_index
```

## Getting Help

If you're still stuck:

1. **Check logs**: `/var/log/postgresql/postgresql-*.log`
2. **Gather diagnostics**:
```sql
-- Run this and share output
SELECT * FROM ttl_worker_status();
SELECT * FROM ttl_summary();
SHOW pg_ttl_index.naptime;
SHOW pg_ttl_index.enabled;
\dx pg_ttl_index
```
3. **GitHub Issues**: [Report a bug](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/issues)
4. **Discussions**: [Ask questions](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/discussions)

## See Also

- [FAQ](../faq.md) - Common questions
- [Configuration](../guides/configuration.md) - Settings reference
- [Monitoring](../guides/monitoring.md) - Health checks
