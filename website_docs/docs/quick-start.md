---
sidebar_position: 3
---

# Quick Start Guide

Get your first TTL index running in under 5 minutes! This guide walks you through a complete example from start to finish.

## Prerequisites

Before starting, ensure you have:
- ✅ Installed the `pg_ttl_index` extension ([Installation Guide](installation.md))
- ✅ Added `pg_ttl_index` to `shared_preload_libraries`
- ✅ Restarted PostgreSQL
- ✅ Created the extension in your database

## Step 1: Start the Background Worker

The background worker is **not started automatically**. Start it first:

```sql
-- Start the TTL background worker
SELECT ttl_start_worker();
```

**Output:**
```
 ttl_start_worker
------------------
 t
```

:::tip Verify Worker is Running
Check the worker status anytime:
```sql
SELECT * FROM ttl_worker_status();
```
:::

## Step 2: Create a Sample Table

Let's create a simple user sessions table:

```sql
-- Create table with timestamp column
CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    session_token TEXT NOT NULL,
    session_data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_activity TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add an index on user_id for better query performance
CREATE INDEX idx_user_sessions_user_id ON user_sessions(user_id);
```

## Step 3: Insert Sample Data

Add some test data with different timestamps:

```sql
-- Insert current sessions
INSERT INTO user_sessions (user_id, session_token, session_data)
VALUES
    (1, 'token_abc123', '{"ip": "192.168.1.1"}'),
    (2, 'token_def456', '{"ip": "192.168.1.2"}'),
    (3, 'token_ghi789', '{"ip": "192.168.1.3"}');

-- Insert old sessions (2 hours ago) for testing
INSERT INTO user_sessions (user_id, session_token, session_data, created_at)
VALUES
    (4, 'token_old001', '{"ip": "192.168.1.4"}', NOW() - INTERVAL '2 hours'),
    (5, 'token_old002', '{"ip": "192.168.1.5"}', NOW() - INTERVAL '2 hours');

-- Check what we have
SELECT id, user_id, created_at, 
       NOW() - created_at AS age
FROM user_sessions
ORDER BY created_at;
```

**Output:**
```
 id | user_id |          created_at           |       age
----+---------+-------------------------------+-----------------
  4 |       4 | 2026-01-03 00:42:00+00        | 02:00:00.123
  5 |       5 | 2026-01-03 00:42:00+00        | 02:00:00.123
  1 |       1 | 2026-01-03 02:42:00+00        | 00:00:00.123
  2 |       2 | 2026-01-03 02:42:00+00        | 00:00:00.123
  3 |       3 | 2026-01-03 02:42:00+00        | 00:00:00.123
```

## Step 4: Set Up TTL Index

Configure the table to automatically delete sessions older than 1 hour (3600 seconds):

```sql
-- Create TTL index: expire after 1 hour
SELECT ttl_create_index(
    'user_sessions',     -- table name
    'created_at',        -- timestamp column
    3600                 -- expire after seconds (1 hour)
);
```

**Output:**
```
 ttl_create_index
------------------
 t
```

:::info What Just Happened?
The function:
1. ✅ Created an index `idx_ttl_user_sessions_created_at` for fast cleanup
2. ✅ Registered the TTL rule in `ttl_index_table`
3. ✅ Activated automatic cleanup for this table
:::

### With Custom Batch Size

For high-volume tables, you can specify a custom batch size:

```sql
-- Larger batch size for tables with millions of rows
SELECT ttl_create_index(
    'user_sessions',
    'created_at',
    3600,
    50000               -- batch size (default is 10000)
);
```

## Step 5: Verify TTL Configuration

Check your TTL configuration:

```sql
-- View all TTL indexes
SELECT * FROM ttl_summary();
```

**Output:**
```
  table_name   | column_name | expire_after_seconds | batch_size | active | last_run | time_since_last_run | rows_deleted_last_run | total_rows_deleted |          index_name
---------------+-------------+----------------------+------------+--------+----------+---------------------+-----------------------+--------------------+-------------------------------
 user_sessions | created_at  |                 3600 |      10000 | t      |          |                     |                     0 |                  0 | idx_ttl_user_sessions_created_at
```

## Step 6: Test Manual Cleanup

Manually trigger cleanup to see it in action:

```sql
-- Manually run cleanup (normally happens every 60 seconds)
SELECT ttl_runner();
```

**Output:**
```
 ttl_runner
------------
          2
```

This means 2 rows were deleted (our old sessions from 2 hours ago).

### Verify Deletion

```sql
-- Check remaining sessions
SELECT id, user_id, created_at,
       NOW() - created_at AS age
FROM user_sessions
ORDER BY created_at;
```

**Output:**
```
 id | user_id |          created_at           |       age
----+---------+-------------------------------+-----------------
  1 |       1 | 2026-01-03 02:42:00+00        | 00:00:00.456
  2 |       2 | 2026-01-03 02:42:00+00        | 00:00:00.456
  3 |       3 | 2026-01-03 02:42:00+00        | 00:00:00.456
```

The old sessions are gone! ✨

## Step 7: Monitor Background Worker

The background worker runs automatically every 60 seconds. Monitor its activity:

```sql
-- Check deletion statistics
SELECT 
    table_name,
    expire_after_seconds,
    last_run,
    time_since_last_run,
    rows_deleted_last_run,
    total_rows_deleted
FROM ttl_summary();
```

**Output:**
```
  table_name   | expire_after_seconds |          last_run          | time_since_last_run | rows_deleted_last_run | total_rows_deleted
---------------+----------------------+----------------------------+---------------------+-----------------------+--------------------
 user_sessions |                 3600 | 2026-01-03 02:42:05.123+00 | 00:00:30            |                     2 |                  2
```

## Complete Example Script

Here's the complete script you can copy and run:

```sql
-- 1. Start background worker
SELECT ttl_start_worker();

-- 2. Create table
CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    session_token TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Insert test data
INSERT INTO user_sessions (user_id, session_token, created_at)
VALUES
    (1, 'active_token', NOW()),
    (2, 'old_token', NOW() - INTERVAL '2 hours');

-- 4. Set up TTL (1 hour expiration)
SELECT ttl_create_index('user_sessions', 'created_at', 3600);

-- 5. Manually trigger cleanup
SELECT ttl_runner();

-- 6. Verify results
SELECT * FROM user_sessions;  -- Should only show recent session
SELECT * FROM ttl_summary();   -- Should show 1 row deleted
```

## Real-World Examples

### Session Management (30-minute expiry)

```sql
CREATE TABLE web_sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER NOT NULL,
    data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

SELECT ttl_create_index('web_sessions', 'created_at', 1800); -- 30 minutes
```

### Application Logs (7-day retention)

```sql
CREATE TABLE app_logs (
    id BIGSERIAL PRIMARY KEY,
    level VARCHAR(10),
    message TEXT,
    metadata JSONB,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

SELECT ttl_create_index('app_logs', 'logged_at', 604800); -- 7 days
```

### Cache Entries (1-hour expiry)

```sql
CREATE TABLE cache_entries (
    cache_key VARCHAR(255) PRIMARY KEY,
    cache_value TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

SELECT ttl_create_index('cache_entries', 'created_at', 3600); -- 1 hour
```

## Common Tasks

### Update Expiry Time

```sql
-- Change from 1 hour to 2 hours
SELECT ttl_create_index('user_sessions', 'created_at', 7200);
```

### Temporarily Disable TTL

```sql
-- Disable without removing
UPDATE ttl_index_table 
SET active = false 
WHERE table_name = 'user_sessions';

-- Re-enable
UPDATE ttl_index_table 
SET active = true 
WHERE table_name = 'user_sessions';
```

### Remove TTL Completely

```sql
-- Removes TTL rule and drops the auto-created index
SELECT ttl_drop_index('user_sessions', 'created_at');
```

### Check Worker Status

```sql
-- See if worker is running
SELECT * FROM ttl_worker_status();

-- Check all TTL configurations
SELECT * FROM ttl_summary();
```

## What's Next?

Now that you have a working TTL setup:

- **[Configuration Guide](guides/configuration.md)** - Tune performance and intervals
- **[Monitoring Guide](guides/monitoring.md)** - Track cleanup activity
- **[API Reference](api/functions.md)** - Learn all available functions
- **[Best Practices](guides/best-practices.md)** - Optimize for production use

## Need Help?

- **[FAQ](faq.md)** - Common questions and answers
- **[Troubleshooting](advanced/troubleshooting.md)** - Solve common issues
- **[GitHub Issues](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/issues)** - Report bugs or ask questions
