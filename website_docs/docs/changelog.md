---
sidebar_position: 2
---

# Changelog

Version history and release notes for `pg_ttl_index`.

## Version 3.0.0 (2026-03-20)

### ✨ New Features

- **Soft delete mode** in `ttl_create_index()` via optional `soft_delete_column`
- `ttl_runner()` now supports marking expired rows instead of hard deleting
- `ttl_summary()` now returns `soft_delete_column` and `cleanup_mode`

### 🔧 Improvements

- Added validation for `batch_size` and `expire_after_seconds`
- Added validation that `soft_delete_column` exists and is `timestamp`/`timestamptz`

## Version 2.0.0 (2026-01-01)

### 🎉 Major Release

Second major version with significant performance improvements and new features.

### ⚠️ Breaking Changes

- **API Change**: `ttl_create_index()` now accepts optional `batch_size` parameter
  - Old: `ttl_create_index(table, column, seconds)`
  - New: `ttl_create_index(table, column, seconds, batch_size DEFAULT 10000)`
  - **Impact**: Existing calls still work (parameter is optional)

### ✨ New Features

#### Batch Deletion
- Configurable batch size for deletion operations
- Default batch size: 10,000 rows
- Prevents long-running transactions
- Yields to other processes between batches (10ms sleep)

#### Auto-Indexing
- Automatically creates indexes on timestamp columns
- Index naming pattern: `idx_ttl_{table}_{column}`
- Significantly improves cleanup performance
- Indexes stored in `ttl_index_table.index_name`

#### Statistics Tracking
- `rows_deleted_last_run`: Tracks last cleanup cycle
- `total_rows_deleted`: Cumulative deletion counter
- `last_run`: Timestamp of last cleanup
- Available via `ttl_summary()` view

#### Concurrency Control
- Advisory lock mechanism prevents overlapping runs
- Safe for clustered environments
- Uses `pg_try_advisory_lock(hashtext('pg_ttl_index_runner'))`
- Automatic lock cleanup on completion

### 🔧 Improvements

- **Enhanced `ttl_summary()`**: Now returns batch_size, deletion stats, and index names
- **Per-table error handling**: Errors in one table don't affect others
- **Better function organization**: Moved `ttl_create_index`/`ttl_drop_index to PL/pgSQL

### 🗑️ Removed Features

- Removed C-based `ttl_create_index`/`ttl_drop_index` (now PL/pgSQL)
- Simpler codebase, easier to maintain

### 📊 Schema Changes

New columns in `ttl_index_table`:
```sql
batch_size INTEGER NOT NULL DEFAULT 10000,
rows_deleted_last_run BIGINT DEFAULT 0,
total_rows_deleted BIGINT DEFAULT 0,
index_name TEXT
```

### 📝 Migration Notes

See [Migration Guide](advanced/migration.md) for detailed upgrade instructions.

### 🐛 Bug Fixes

- Fixed race condition in worker cleanup
- Improved error messages for invalid column types
- Better handling of dropped tables

---

## Version 1.0.2 (Deprecated)

### Initial Stable Release

First production-ready version.

### Features

- Basic TTL functionality
- Background worker for automatic cleanup
- `ttl_create_index()` and `ttl_drop_index()` functions
- `ttl_runner()` for manual cleanup
- `ttl_worker_status()` for monitoring
- Simple `ttl_summary()` view

### Limitations

- No batch deletion (single large DELETE)
- Manual index creation required
- No statistics tracking
- No concurrency control

---

## Version 1.0 (Deprecated)

### Initial Development Version

Proof of concept release.

### Features

- Basic cleanup mechanism
- Manual execution only (no background worker)
- Simple configuration table

### Known Issues

- Not production-ready
- No error handling
- Performance issues with large tables

---

## Upgrade Path

### Version 3.0.0 Policy

`3.0.0` is distributed as a clean release without SQL upgrade scripts from previous versions.
Use a fresh install path for `3.0.0` deployments. See [Migration Guide](advanced/migration.md).

---

## Release Schedule

- **Major versions** (x.0.0): Significant features, possible breaking changes
- **Minor versions** (x.y.0): New features, backward compatible
- **Patch versions** (x.y.z): Bug fixes only

---

## Planned Features (Roadmap)

Future versions may include:

- **Parallel cleanup** across multiple tables
- **Automatic worker restart** after PostgreSQL restart
- **Cleanup scheduling** (specific time windows)
- **Per-table cleanup frequency** override
- **Integration with pg_cron** for advanced scheduling
- **Data archival** before deletion

Vote for features on [GitHub Discussions](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/discussions)!

---

## Version Compatibility

| Extension Version | PostgreSQL Version | Status |
|-------------------|-------------------|---------|
| 3.0.0 | 12.0+ | ✅ Supported |
| 2.0.0 | 12.0+ | ⚠️ Legacy |
| 1.0.2 | 12.0+ | ⚠️ Deprecated |
| 1.0 | 12.0+ | ❌ Unsupported |

---

## Getting Updates

- **GitHub Releases**: [github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/releases](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/releases)
- **PGXN**: [pgxn.org/dist/pg_ttl_index](https://pgxn.org/dist/pg_ttl_index/)

## See Also

- [Installation Guide](installation.md) - How to install/upgrade
- [Migration Guide](advanced/migration.md) - Migration and reinstall guidance
- [API Reference](api/functions.md) - Function documentation
