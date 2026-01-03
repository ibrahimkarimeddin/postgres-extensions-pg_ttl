---
sidebar_position: 1
---

# Introduction to pg_ttl_index

**pg_ttl_index** is a high-performance PostgreSQL extension that provides automatic Time-To-Live (TTL) functionality for database tables. It automatically deletes expired data based on timestamp columns, helping you maintain clean databases without manual intervention.

## What is TTL?

Time-To-Live (TTL) is a mechanism for automatically expiring and removing data after a specified time period. This is essential for:

- **Session management** - Auto-expire user sessions after inactivity
- **Log cleanup** - Remove old application logs automatically
- **Cache management** - Clear stale cache entries
- **Audit trail retention** - Maintain compliance by deleting old audit records
- **Temporary data** - Clean up temporary records that are no longer needed

## Key Features

### ✅ Automatic Data Expiration
Set up TTL rules once, and the extension handles the rest. No cron jobs, no manual cleanup scripts.

### ✅ Background Worker
Runs cleanup at configurable intervals (default: 60 seconds). Automatically processes all tables with active TTL indexes.

### ✅ High-Performance Batch Deletion (v2.0+)
- Configurable batch sizes (default: 10,000 rows)
- Efficiently handles millions of rows
- Uses `ctid` for optimal delete performance
- Yields to other processes between batches

### ✅ Auto-Indexing (v2.0+)
Automatically creates indexes on timestamp columns for fast cleanup operations.

### ✅ Stats Tracking (v2.0+)
- Monitor rows deleted per table
- Track last cleanup time
- View total deletion statistics
- Built-in summary views

### ✅ Concurrency Control (v2.0+)
Advisory locks prevent overlapping cleanup runs, ensuring safe operation in clustered environments.

### ✅ Multiple Tables Support
Different expiry times per table - each table can have its own TTL configuration.

### ✅ Production Ready
- ACID compliant transactions
- Per-table error handling (errors in one table don't affect others)
- SQL injection protection
- Comprehensive monitoring functions

## Quick Example

```sql
-- Create a table with a timestamp column
CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    session_data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Start the background worker
SELECT ttl_start_worker();

-- Set up TTL: data expires after 1 hour (3600 seconds)
SELECT ttl_create_index('user_sessions', 'created_at', 3600);

-- That's it! The background worker will automatically delete 
-- rows older than 1 hour every 60 seconds.
```

## Version History

### Version 2.0.0 (Current)
- **Batch deletion** with configurable batch size
- **Auto-indexing** of timestamp columns
- **Stats tracking** (rows deleted per table)
- **Advisory lock** concurrency control
- Improved per-table error handling

### Version 1.0.x (Deprecated)
- Basic TTL functionality
- Simple background worker
- Limited to basic use cases

## Use Cases

### Session Management
Automatically clean up expired user sessions to prevent database bloat:

```sql
SELECT ttl_create_index('sessions', 'last_activity', 1800); -- 30 minutes
```

### Application Logs
Keep logs for analysis but automatically remove old entries:

```sql
SELECT ttl_create_index('app_logs', 'logged_at', 604800); -- 7 days
```

### Cache Tables
Implement time-based cache expiration:

```sql
SELECT ttl_create_index('cache_entries', 'expires_at', 0); -- Immediate
```

### Temporary Data
Clean up temporary processing tables:

```sql
SELECT ttl_create_index('temp_imports', 'created_at', 3600); -- 1 hour
```

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│         PostgreSQL Database                 │
│                                             │
│  ┌────────────────────────────────────┐    │
│  │  Background Worker (per database)  │    │
│  │  - Runs every 60 seconds          │    │
│  │  - Processes all active TTL rules │    │
│  └────────────────────────────────────┘    │
│                    │                        │
│                    ▼                        │
│  ┌────────────────────────────────────┐    │
│  │    ttl_index_table                │    │
│  │  - Stores TTL configuration       │    │
│  │  - Tracks deletion statistics     │    │
│  └────────────────────────────────────┘    │
│                    │                        │
│                    ▼                        │
│  ┌────────────────────────────────────┐    │
│  │  Your Tables (with TTL enabled)   │    │
│  │  - user_sessions                  │    │
│  │  - app_logs                       │    │
│  │  - cache_entries                  │    │
│  └────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

## Requirements

- **PostgreSQL**: Version 12.0 or higher
- **Privileges**: Superuser access for installation
- **Restart capability**: Required to load the extension

## Next Steps

Ready to get started? Follow our guides:

1. **[Installation Guide](installation.md)** - Install via PGXN or from source
2. **[Quick Start](quick-start.md)** - Get your first TTL index running
3. **[Configuration](guides/configuration.md)** - Fine-tune for your workload
4. **[API Reference](api/functions.md)** - Complete function documentation

## Support

- **GitHub**: [github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl)
- **Issues**: [Report bugs or request features](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/issues)
- **PGXN**: [pgxn.org/dist/pg_ttl_index](https://pgxn.org/dist/pg_ttl_index/)
