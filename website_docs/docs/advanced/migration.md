---
sidebar_position: 4
---

# Migration Guide

Upgrading from v1.0.x to v2.0.0.

## Overview

Version 2.0.0 includes significant performance improvements and new features, but also introduces breaking changes.

## Breaking Changes

### 1. ttl_create_index() Function Signature

**Before (v1.0.x)**:
```sql
ttl_create_index(table_name TEXT, column_name TEXT, expire_after_seconds INTEGER)
```

**After (v2.0.0)**:
```sql
ttl_create_index(
    table_name TEXT,
    column_name TEXT,
    expire_after_seconds INTEGER,
    batch_size INTEGER DEFAULT 10000  -- NEW PARAMETER
)
```

**Impact**: Existing calls still work (new parameter is optional)

**Action Required**: None, but consider specifying batch_size for high-volume tables

### 2. ttl_index_table Schema Changes

**New Columns Added**:
- `batch_size INTEGER DEFAULT 10000`
- `rows_deleted_last_run BIGINT DEFAULT 0`
- `total_rows_deleted BIGINT DEFAULT 0`
- `index_name TEXT`

**Impact**: Automatic schema migration on extension update

**Action Required**: None

## Migration Steps

### Step 1: Backup

```sql
-- Backup TTL configuration
COPY ttl_index_table TO '/backup/ttl_config_v1.csv' CSV HEADER;

-- Backup data (optional but recommended)
pg_dump -d your_database > /backup/pre_migration.sql
```

### Step 2: Update Extension Files

```bash
# Via PGXN
pgxn install pg_ttl_index

# Or from source
cd postgres-extensions-pg_ttl
git pull
make
sudo make install
```

### Step 3: Stop Background Worker

```sql
-- Stop v1.0 worker
SELECT ttl_stop_worker();

-- Verify stopped
SELECT * FROM ttl_worker_status();
-- Should return no rows
```

### Step 4: Update Extension

```sql
-- Restart PostgreSQL (required for shared library update)
\! sudo systemctl restart postgresql

-- Reconnect and update extension
\c your_database

ALTER EXTENSION pg_ttl_index UPDATE TO '2.0.0';

-- Verify version
\dx pg_ttl_index
```

### Step 5: Restart Background Worker

```sql
-- Start v2.0 worker
SELECT ttl_start_worker();

-- Verify running
SELECT * FROM ttl_worker_status();
```

### Step 6: Verify Migration

```sql
-- Check TTL configuration
SELECT * FROM ttl_summary();

-- Verify new columns exist
\d ttl_index_table
```

## Post-Migration Optimization

### Review Batch Sizes

```sql
-- Check default batch sizes (10000)
SELECT table_name, batch_size
FROM ttl_index_table;

-- Adjust for high-volume tables
UPDATE ttl_index_table
SET batch_size = 50000
WHERE table_name = 'high_volume_table';

-- Or recreate with new batch size
SELECT ttl_create_index('high_volume_table', 'created_at', 3600, 50000);
```

### Monitor New Statistics

```sql
-- View deletion statistics
SELECT 
    table_name,
    rows_deleted_last_run,
    total_rows_deleted,
    index_name
FROM ttl_summary();
```

## New Features to Leverage

### 1. Batch Deletion

Automatically enabled, no configuration needed. Adjust `batch_size` as needed:

```sql
SELECT ttl_create_index('table', 'timestamp', 3600, 25000);
```

### 2. Auto-Indexing

Indexes are created automatically. Verify:

```sql
SELECT index_name FROM ttl_index_table WHERE table_name = 'your_table';

-- Check index exists
\di+ idx_ttl_your_table_*
```

### 3. Stats Tracking

Monitor cleanup effectiveness:

```sql
SELECT 
    table_name,
    total_rows_deleted,
    rows_deleted_last_run,
    last_run
FROM ttl_summary()
ORDER BY total_rows_deleted DESC;
```

### 4. Concurrency Control

Advisory locks prevent overlapping runs. No configuration needed.

## Rollback (If Needed)

If you encounter issues and need to rollback:

### Step 1: Downgrade Extension

```sql
ALTER EXTENSION pg_ttl_index UPDATE TO '1.0.2';
```

### Step 2: Restore Configuration

```sql
-- Truncate and restore from backup
TRUNCATE ttl_index_table;
COPY ttl_index_table FROM '/backup/ttl_config_v1.csv' CSV HEADER;
```

### Step 3: Restart Worker

```sql
SELECT ttl_start_worker();
```

## Compatibility

### PostgreSQL Versions

- v1.0.x: PostgreSQL 12+
- v2.0.0: PostgreSQL 12+

Both versions support the same PostgreSQL versions.

### Extension Dependencies

- None (standalone extension)

## Frequently Asked Questions

**Q: Will my existing TTL configurations stop working?**

A: No, they will continue to work with default batch_size of 10,000.

**Q: Do I need to recreate my TTL indexes?**

A: No, existing indexes are automatically migrated.

**Q: What happens to my deletion statistics?**

A: Historical data is lost (starts from 0), but future deletions are tracked.

**Q: Can I upgrade without downtime?**

A: PostgreSQL restart is required for shared library update, so there will be brief downtime.

## See Also

- [Changelog](../changelog.md) - Full version history
- [Installation](../installation.md) - Fresh installation guide
- [Configuration](../guides/configuration.md) - Tuning new features
