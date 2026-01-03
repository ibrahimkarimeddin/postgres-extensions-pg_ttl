---
sidebar_position: 3
---

# Configuration Parameters

PostgreSQL configuration parameters (GUCs) for `pg_ttl_index`.

## Parameters Overview

| Parameter | Type | Default | Restart Required | Description |
|-----------|------|---------|------------------|-------------|
| `pg_ttl_index.naptime` | integer | `60` | No | Cleanup interval in seconds |
| `pg_ttl_index.enabled` | boolean | `true` | No | Enable/disable background worker |

## pg_ttl_index.naptime

Controls how often the background worker runs cleanup operations.

### Details

- **Type**: Integer
- **Unit**: Seconds
- **Default**: `60`
- **Min**: `1`
- **Max**: `3600` (1 hour)
- **Context**: `SIGHUP` (reload configuration)

### Usage

```sql
-- View current setting
SHOW pg_ttl_index.naptime;

-- Change to 30 seconds
ALTER SYSTEM SET pg_ttl_index.naptime = 30;
SELECT pg_reload_conf();

-- Or in postgresql.conf
-- pg_ttl_index.naptime = 30
```

### Recommendations

| Use Case | Recommended Value | Reason |
|----------|-------------------|--------|
| High-volume cleanup | `30` | More frequent cleanup prevents backlog |
| Normal workload | `60` | Default, balances frequency and overhead |
| Low-volume tables | `120-300` | Less frequent checks reduce overhead |
| Development/testing | `10-20` | Faster feedback during testing |

### Performance Impact

- **Lower values** = More frequent cleanup = Higher CPU usage
- **Higher values** = Less frequent cleanup = Potential data buildup

## pg_ttl_index.enabled

Globally enables or disables the background worker.

### Details

- **Type**: Boolean
- **Default**: `true`
- **Context**: `SIGHUP` (reload configuration)

### Usage

```sql
-- View current setting
SHOW pg_ttl_index.enabled;

-- Disable background worker
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();

-- Re-enable
ALTER SYSTEM SET pg_ttl_index.enabled = true;
SELECT pg_reload_conf();
```

### Use Cases

**Disable during maintenance:**
```sql
-- Before heavy operations
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();

-- Perform maintenance
-- ...

-- Re-enable
ALTER SYSTEM SET pg_ttl_index.enabled = true;
SELECT pg_reload_conf();
```

**Temporarily stop all cleanup:**
```sql
-- Alternative to stopping worker
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();
```

## shared_preload_libraries

:::warning Required Configuration
`pg_ttl_index` **must** be in `shared_preload_libraries` to function.
:::

### Configuration

Edit `postgresql.conf`:

```conf
shared_preload_libraries = 'pg_ttl_index'
```

Multiple extensions:
```conf
shared_preload_libraries = 'pg_stat_statements,pg_ttl_index'
```

### Verification

```sql
-- Check if extension is preloaded
SHOW shared_preload_libraries;

-- Should include: 'pg_ttl_index'
```

**Note**: Requires PostgreSQL restart to take effect.

## Viewing All Settings

### Show All pg_ttl_index Parameters

```sql
SELECT 
    name,
    setting,
    unit,
    context,
    short_desc
FROM pg_settings
WHERE name LIKE 'pg_ttl_index%';
```

**Example Output:**
```
        name           | setting | unit  | context |           short_desc
-----------------------+---------+-------+---------+----------------------------------
 pg_ttl_index.enabled  | on      |       | sighup  | Enable TTL background worker
 pg_ttl_index.naptime  | 60      | s     | sighup  | Cleanup interval in seconds
```

## Configuration File Management

### Using ALTER SYSTEM

```sql
-- Change settings (preferred method)
ALTER SYSTEM SET pg_ttl_index.naptime = 45;
ALTER SYSTEM SET pg_ttl_index.enabled = true;

-- Reload configuration
SELECT pg_reload_conf();

-- Verify changes
SHOW pg_ttl_index.naptime;
```

This modifies `postgresql.auto.conf` automatically.

### Using postgresql.conf

Edit the main configuration file:

```bash
sudo nano /etc/postgresql/16/main/postgresql.conf
```

Add or modify:
```conf
# TTL Extension Configuration
shared_preload_libraries = 'pg_ttl_index'
pg_ttl_index.naptime = 60
pg_ttl_index.enabled = true
```

Reload:
```bash
sudo systemctl reload postgresql
# or
SELECT pg_reload_conf();
```

## Reload vs Restart

| Change | Requires Restart? | Command |
|--------|-------------------|---------|
| `shared_preload_libraries` | **Yes** | `systemctl restart postgresql` |
| `pg_ttl_index.naptime` | **No** | `SELECT pg_reload_conf();` |
| `pg_ttl_index.enabled` | **No** | `SELECT pg_reload_conf();` |

## Configuration Best Practices

### Production Settings

```conf
# Production recommended settings
pg_ttl_index.naptime = 60        # Standard cleanup interval
pg_ttl_index.enabled = true      # Always enabled
```

### Development Settings

```conf
# Development/testing settings
pg_ttl_index.naptime = 10        # Faster feedback during testing
pg_ttl_index.enabled = true
```

### High-Load Systems

```conf
# High-volume deletion workloads
pg_ttl_index.naptime = 30        # More frequent cleanup
pg_ttl_index.enabled = true
```

### Low-Priority Cleanup

```conf
# When cleanup is low priority
pg_ttl_index.naptime = 300       # 5-minute interval
pg_ttl_index.enabled = true
```

## Troubleshooting Configuration

### Settings Not Taking Effect

**Problem**: Changed `naptime` but worker still uses old value.

**Solution**:
```sql
-- Reload configuration
SELECT pg_reload_conf();

-- Verify new value
SHOW pg_ttl_index.naptime;

-- Restart worker to pick up changes
SELECT ttl_stop_worker();
SELECT ttl_start_worker();
```

### Worker Not Starting

**Problem**: Worker doesn't start even with correct configuration.

**Check**:
```sql
-- 1. Verify extension is preloaded
SHOW shared_preload_libraries;

-- 2. Check if enabled
SHOW pg_ttl_index.enabled;

-- 3. Look for errors in PostgreSQL logs
-- tail -f /var/log/postgresql/postgresql-*.log

-- 4. Try manual start
SELECT ttl_start_worker();
```

### Permission Denied on ALTER SYSTEM

**Problem**: `ERROR: permission denied to set parameter`

**Solution**:
```sql
-- Must be superuser or have pg_write_server_files role
\du

-- Or edit postgresql.conf directly (requires OS access)
```

## Monitoring Configuration Changes

### Track Configuration History

```sql
-- View current configuration
SELECT name, setting, source, sourcefile, sourceline
FROM pg_settings
WHERE name LIKE 'pg_ttl_index%';
```

### Log Configuration on Startup

Add to `postgresql.conf`:
```conf
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
log_connections = on
log_disconnections = on
```

Then check logs for extension loading messages.

## Related Documentation

- [Functions API](functions.md) - `ttl_start_worker()`, `ttl_stop_worker()`
- [Monitoring](../guides/monitoring.md) - Track worker activity
- [Performance Tuning](../advanced/performance.md) - Optimize cleanup intervals
