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
10. [Support](#support)

## Overview

The `pg_ttl_index` extension provides automatic Time-To-Live (TTL) functionality for PostgreSQL tables. It automatically deletes expired data based on timestamp columns, helping you maintain clean databases without manual intervention.

### Key Features
- ✅ **Automatic data expiration** - Set it and forget it
- ✅ **Background worker** - Runs cleanup at configurable intervals
- ✅ **Batch deletion** - Handles millions of rows efficiently (v2.0+)
- ✅ **Auto-indexing** - Creates index on timestamp column automatically (v2.0+)
- ✅ **Stats tracking** - Monitor rows deleted per table (v2.0+)
- ✅ **Concurrency control** - Advisory locks prevent overlapping runs (v2.0+)
- ✅ **Multiple tables support** - Different expiry times per table
- ✅ **Production ready** - ACID compliant with SQL injection protection

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
-- Optional: specify batch_size for high-load tables (default: 10000)
SELECT ttl_create_index('user_sessions', 'created_at', 3600);

-- Or with custom batch size for high-volume tables
SELECT ttl_create_index('user_sessions', 'created_at', 3600, 5000);
```

### 4. Verify TTL Index

```sql
-- Check active TTL indexes with stats
SELECT * FROM ttl_summary();
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

-- Sessions expire after 24 hours (batch size 5000 for high load)
SELECT ttl_create_index('sessions', 'created_at', 86400, 5000);
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

### Managing TTL Indexes

```sql
-- List all TTL indexes with stats
SELECT * FROM ttl_summary();

-- Returns:
-- table_name, column_name, expire_after_seconds, batch_size,
-- active, last_run, time_since_last_run, rows_deleted_last_run,
-- total_rows_deleted, index_name

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

-- Remove TTL index completely (also drops the auto-created index)
SELECT ttl_drop_index('user_sessions', 'created_at');
```

## Background Worker Management

### Starting the Background Worker

The background worker is **not started automatically**. You must start it manually:

```sql
-- Start the background worker
SELECT ttl_start_worker();

-- Check if worker is running
SELECT * FROM ttl_worker_status();
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
-- View background worker status
SELECT * FROM ttl_worker_status();
```

### Monitor Cleanup Activity

```sql
-- Check deletion stats and last cleanup times
SELECT 
    table_name,
    rows_deleted_last_run,
    total_rows_deleted,
    last_run,
    time_since_last_run
FROM ttl_summary();
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
pgxn install pg_ttl_index

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


## Support

- **GitHub Repository:** https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl
- **Issues:** https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/issues
- **Documentation:** This user guide
