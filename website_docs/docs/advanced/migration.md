---
sidebar_position: 4
---

# Migration Guide

This page explains how to move to `pg_ttl_index` `3.0.0`.

## Important

`3.0.0` is published as a clean release and does not include SQL upgrade scripts from earlier versions.

If you are on an older version, migrate with backup/reinstall steps below.

## Recommended Migration Flow

### 1. Backup Existing TTL Configuration

```sql
COPY ttl_index_table TO '/tmp/ttl_index_table_backup.csv' CSV HEADER;
```

### 2. Stop Worker

```sql
SELECT ttl_stop_worker();
```

### 3. Remove Old Extension

```sql
DROP EXTENSION pg_ttl_index CASCADE;
```

### 4. Install and Create `3.0.0`

Install extension files on the server (`make install` or PGXN), then:

```sql
CREATE EXTENSION pg_ttl_index;
```

### 5. Recreate TTL Rules

Recreate rules using `ttl_create_index(...)` from your backup.

Hard delete mode:

```sql
SELECT ttl_create_index('public.sessions', 'created_at', 3600, 10000);
```

Soft delete mode:

```sql
SELECT ttl_create_index('public.sessions', 'created_at', 3600, 10000, 'deleted_at');
```

### 6. Start Worker and Verify

```sql
SELECT ttl_start_worker();
SELECT * FROM ttl_summary();
SELECT * FROM ttl_worker_status();
```

## Notes

- Prefer schema-qualified table names, for example `public.sessions`.
- Soft delete requires a nullable `timestamp` or `timestamptz` column.
