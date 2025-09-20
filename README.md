# PostgreSQL TTL Index Extension - User Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Installation](#installation)
4. [Quick Start](#quick-start)
5. [Usage Examples](#usage-examples)
6. [Background Worker Management](#background-worker-management)
7. [Configuration](#configuration)
8. [Monitoring](#monitoring)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)
11. [Support](#support)

## Overview

The `pg_ttl_index` extension provides automatic Time-To-Live (TTL) functionality for PostgreSQL tables. It automatically deletes expired data based on timestamp columns, helping you maintain clean databases without manual intervention.

### Key Features
- ✅ **Automatic data expiration** - Set it and forget it
- ✅ **Background worker** - Runs cleanup every minute (manual start required)
- ✅ **Multiple tables support** - Different expiry times per table
- ✅ **Production ready** - ACID compliant with SQL injection protection
- ✅ **Configurable** - Adjustable cleanup intervals
- ✅ **Zero downtime** - No impact on your application performance
- ✅ **Manual control** - Start/stop worker as needed

## Prerequisites

Before installing the extension, ensure you have:

- **PostgreSQL 12.0+** (tested on PostgreSQL 12-16)
- **Development tools** (make, gcc, postgresql-server-dev)
- **Superuser privileges** for installation
- **Database restart capability** (for shared_preload_libraries)


## Installation

### Option 1: Install via PGXN (Recommended)

```bash
# Install using PGXN (PostgreSQL Extension Network)
pgxn install pg_ttl_index
```

**Note:** PGXN installation requires the `pgxn` client tool. Install it with:
```bash
# Ubuntu/Debian
sudo apt-get install pgxnclient

# macOS
brew install pgxnclient

# Or install via pip
pip install pgxnclient
```


### Step 2: Configure PostgreSQL

Add the extension to your PostgreSQL configuration:

```bash
# Edit postgresql.conf
sudo nano /etc/postgresql/12/main/postgresql.conf
```

Add or modify this line:
```
shared_preload_libraries = 'pg_ttl_index'
```

**Note:** If you already have other extensions in `shared_preload_libraries`, separate them with commas:
```
shared_preload_libraries = 'pg_stat_statements,pg_ttl_index'
```

### Step 3: Restart PostgreSQL

```bash
# Ubuntu/Debian
sudo systemctl restart postgresql

# macOS (Homebrew)
brew services restart postgresql
```

### Step 4: Create the Extension

Connect to your database and create the extension:

```sql
-- Connect to your database
\c your_database_name

-- Create the extension
CREATE EXTENSION pg_ttl_index;

-- Start the background worker (required for automatic cleanup)
SELECT ttl_start_worker();

-- Verify installation
\dx pg_ttl_index
```

## Quick Start

### 1. Start the Background Worker

```sql
-- Start the background worker for automatic cleanup
SELECT ttl_start_worker();
```

### 2. Create a Sample Table

```sql
-- Create a table with a timestamp column
CREATE TABLE user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    session_data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insert some test data
INSERT INTO user_sessions (user_id, session_data) VALUES 
(1, '{"login_time": "2024-01-01 10:00:00"}'),
(2, '{"login_time": "2024-01-01 11:00:00"}'),
(3, '{"login_time": "2024-01-01 12:00:00"}');
```

### 3. Set Up TTL Index

```sql
-- Data expires after 1 hour (3600 seconds)
SELECT ttl_create_index('user_sessions', 'created_at', 3600);
```

### 4. Verify TTL Index

```sql
-- Check active TTL indexes
SELECT * FROM ttl_index_table;
```

### 5. Test the Cleanup

```sql
-- Manually trigger cleanup (optional - runs automatically via background worker)
SELECT ttl_runner();
```

## Usage Examples

### Example 1: Session Management

```sql
-- Create sessions table
CREATE TABLE sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER NOT NULL,
    data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Sessions expire after 24 hours
SELECT ttl_create_index('sessions', 'created_at', 86400);
```

### Example 2: Log Cleanup

```sql
-- Create application logs table
CREATE TABLE app_logs (
    id SERIAL PRIMARY KEY,
    level VARCHAR(10) NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Logs expire after 7 days
SELECT ttl_create_index('app_logs', 'logged_at', 604800);
```

### Example 3: Cache Management

```sql
-- Create cache table
CREATE TABLE cache_entries (
    cache_key VARCHAR(255) PRIMARY KEY,
    cache_value TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);

-- Cache expires based on expires_at column
SELECT ttl_create_index('cache_entries', 'expires_at', 0);
```

### Example 4: Multiple TTL Indexes

```sql
-- Create a comprehensive logging table
CREATE TABLE system_events (
    id SERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    severity VARCHAR(10) NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);

-- Different retention policies
SELECT ttl_create_index('system_events', 'created_at', 2592000);  -- 30 days for all events
SELECT ttl_create_index('system_events', 'processed_at', 604800); -- 7 days for processed events
```

### Managing TTL Indexes

```sql
-- List all TTL indexes
SELECT 
    table_name,
    column_name,
    expire_after_seconds,
    active,
    created_at,
    last_run
FROM ttl_index_table
ORDER BY created_at DESC;

-- Update expiry time
SELECT ttl_create_index('user_sessions', 'created_at', 7200); -- Change to 2 hours

-- Disable TTL index (temporarily)
UPDATE ttl_index_table 
SET active = false 
WHERE table_name = 'user_sessions' AND column_name = 'created_at';

-- Re-enable TTL index
UPDATE ttl_index_table 
SET active = true 
WHERE table_name = 'user_sessions' AND column_name = 'created_at';

-- Remove TTL index completely
SELECT ttl_drop_index('user_sessions', 'created_at');
```

## Background Worker Management

### Starting the Background Worker

The background worker is **not started automatically**. You must start it manually:

```sql
-- Start the background worker
SELECT ttl_start_worker();

-- Check if worker is running
SELECT 
    pid,
    usename,
    application_name,
    state,
    query_start
FROM pg_stat_activity 
WHERE application_name LIKE '%TTL%';
```

### Important Notes

- **Manual Start Required**: The worker does not start automatically after extension installation
- **Per-Database**: You need to start the worker in each database where you want TTL functionality
- **Restart Required**: If PostgreSQL restarts, you'll need to start the worker again
- **Single Worker**: Only one TTL worker runs per database

## Configuration

### Background Worker Settings

```sql
-- Change cleanup interval (default: 60 seconds)
ALTER SYSTEM SET pg_ttl_index.naptime = 30;
SELECT pg_reload_conf();

-- Disable background worker temporarily
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();

-- Re-enable background worker
ALTER SYSTEM SET pg_ttl_index.enabled = true;
SELECT pg_reload_conf();
```

### View Current Configuration

```sql
-- Check current settings
SELECT name, setting, unit, context 
FROM pg_settings 
WHERE name LIKE 'pg_ttl_index%';
```

## Monitoring

### Check Background Worker Status

```sql
-- View background worker processes
SELECT 
    pid,
    usename,
    application_name,
    state,
    query_start,
    query
FROM pg_stat_activity 
WHERE application_name LIKE '%TTL%';
```

### Monitor Cleanup Activity

```sql
-- Check last cleanup times
SELECT 
    table_name,
    column_name,
    last_run,
    NOW() - last_run AS time_since_last_run
FROM ttl_index_table 
WHERE active = true
ORDER BY last_run DESC;
```

### View PostgreSQL Logs

```bash
# Check PostgreSQL logs for TTL activity
sudo tail -f /var/log/postgresql/postgresql-12-main.log | grep TTL
```

## Troubleshooting

### Common Issues

#### 1. Extension Not Loading

**Error:** `ERROR: extension "pg_ttl_index" is not available`

**Solution:**
```bash
# Check if extension files are installed
ls -la /usr/share/postgresql/12/extension/pg_ttl_index*

# Reinstall if missing
sudo make install
```

#### 2. Background Worker Not Starting

**Error:** No TTL worker processes visible

**Solution:**
```sql
-- Check if extension is created
\dx pg_ttl_index

-- Check shared_preload_libraries setting
SHOW shared_preload_libraries;

-- Restart PostgreSQL after adding to shared_preload_libraries
```

#### 3. Permission Denied

**Error:** `ERROR: permission denied for table ttl_index_table`

**Solution:**
```sql
-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO your_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ttl_index_table TO your_user;
```

#### 4. Invalid Column Type

**Error:** `Column must be a date/timestamp type`

**Solution:**
```sql
-- Check column data type
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'your_table';

-- Supported types: timestamp, timestamptz, date
```

### Debug Mode

```sql
-- Enable debug logging
ALTER SYSTEM SET log_min_messages = debug1;
SELECT pg_reload_conf();

-- Check logs for detailed TTL activity
```

## Best Practices

### 1. Choose Appropriate Expiry Times

```sql
-- Good examples:
SELECT ttl_create_index('sessions', 'created_at', 3600);     -- 1 hour
SELECT ttl_create_index('logs', 'created_at', 2592000);     -- 30 days
SELECT ttl_create_index('cache', 'expires_at', 0);          -- Immediate expiry

-- Avoid very short intervals (less than 60 seconds)
-- The background worker runs every minute by default
```

### 2. Use Appropriate Column Types

```sql
-- Recommended column types:
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()  -- Best choice
updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()  -- Good for updates
expires_at TIMESTAMPTZ NOT NULL                -- For explicit expiry
created_date DATE NOT NULL DEFAULT CURRENT_DATE -- For daily cleanup
```

### 3. Monitor Performance

```sql
-- Check table sizes before/after cleanup
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE tablename IN ('user_sessions', 'app_logs', 'cache_entries');
```

### 4. Backup Before Major Changes

```sql
-- Always backup before modifying TTL settings
pg_dump your_database > backup_before_ttl_changes.sql
```

### 5. Test in Development First

```sql
-- Test TTL functionality in development
SELECT ttl_create_index('test_table', 'created_at', 60); -- 1 minute for testing
-- Insert test data and verify cleanup
```

## Support

- **GitHub Repository:** https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl
- **Issues:** https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/issues
- **Documentation:** This user guide



