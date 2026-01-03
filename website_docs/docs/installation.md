---
sidebar_position: 2
---

# Installation Guide

This guide covers all installation methods for the `pg_ttl_index` extension.

## Prerequisites

Before installing, ensure you have:

- **PostgreSQL**: Version 12.0 or higher
- **Development tools**: 
  - `make`
  - `gcc` or compatible C compiler
  - `postgresql-server-dev` package (for building extensions)
- **Superuser privileges**: Required for creating the extension
- **Database restart capability**: Needed for loading shared libraries

### Check Your PostgreSQL Version

```bash
psql --version
# or
SELECT version();
```

## Installation Methods

### Option 1: Install via PGXN (Recommended)

The easiest way to install is through the PostgreSQL Extension Network (PGXN):

```bash
# Install using PGXN client
pgxn install pg_ttl_index
```

#### Installing PGXN Client

If you don't have the PGXN client installed:

```bash
# Ubuntu/Debian
sudo apt-get install pgxnclient

# macOS (Homebrew)
brew install pgxnclient

# Or install via pip
pip install pgxnclient
```

### Option 2: Install from Source

#### Clone the Repository

```bash
git clone https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl.git
cd postgres-extensions-pg_ttl
```

#### Build and Install

```bash
# Build the extension
make

# Install (requires sudo/superuser)
sudo make install
```

#### Verify Installation

```bash
# Check if extension files are installed
ls -la $(pg_config --sharedir)/extension/pg_ttl_index*
```

## PostgreSQL Configuration

After installing the extension files, you need to configure PostgreSQL to load the extension.

### Step 1: Edit postgresql.conf

Add `pg_ttl_index` to the `shared_preload_libraries` parameter:

```bash
# Find your postgresql.conf location
psql -c "SHOW config_file;"

# Edit the file (Ubuntu/Debian example)
sudo nano /etc/postgresql/16/main/postgresql.conf
```

Add or modify this line:

```conf
shared_preload_libraries = 'pg_ttl_index'
```

:::tip Multiple Extensions
If you already have other extensions loaded, separate them with commas:
```conf
shared_preload_libraries = 'pg_stat_statements,pg_ttl_index'
```
:::

### Step 2: Restart PostgreSQL

The extension must be loaded at server startup:

```bash
# Ubuntu/Debian
sudo systemctl restart postgresql

# macOS (Homebrew)
brew services restart postgresql

# Or using pg_ctl
pg_ctl restart -D /path/to/data/directory
```

### Step 3: Verify Server Startup

Check that PostgreSQL started successfully and loaded the extension:

```bash
# Check server status
sudo systemctl status postgresql

# Check PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-16-main.log
```

Look for messages like:
```
LOG:  pg_ttl_index extension loaded
```

## Database Setup

Now create the extension in your database:

### Step 1: Connect to Your Database

```bash
# Connect via psql
psql -U postgres -d your_database_name
```

### Step 2: Create the Extension

```sql
-- Create the extension
CREATE EXTENSION pg_ttl_index;

-- Verify extension was created
\dx pg_ttl_index
```

Expected output:
```
        Name        | Version |   Schema   |              Description
--------------------+---------+------------+----------------------------------------
 pg_ttl_index      | 2.0.0   | public     | Automatic TTL for PostgreSQL tables
```

### Step 3: Start the Background Worker

:::warning Important
The background worker does **not** start automatically. You must start it manually in each database.
:::

```sql
-- Start the background worker
SELECT ttl_start_worker();
```

Expected output:
```
 ttl_start_worker
------------------
 t
(1 row)
```

### Step 4: Verify Worker is Running

```sql
-- Check worker status
SELECT * FROM ttl_worker_status();
```

You should see a worker process running for your database.

## Verification

Run these commands to verify the installation is complete:

```sql
-- List all TTL functions
SELECT proname, prosrc 
FROM pg_proc 
WHERE proname LIKE 'ttl_%' 
ORDER BY proname;

-- Check if background worker is running
SELECT * FROM ttl_worker_status();

-- View current TTL configuration
SELECT name, setting, unit 
FROM pg_settings 
WHERE name LIKE 'pg_ttl_index%';
```

## Troubleshooting Installation

### Extension Files Not Found

**Error**: `ERROR: could not open extension control file`

**Solution**:
```bash
# Verify extension files are installed
ls -la $(pg_config --sharedir)/extension/pg_ttl_index*

# If missing, reinstall
sudo make install
```

### Shared Library Not Found

**Error**: `ERROR: could not load library`

**Solution**:
```bash
# Check if shared library exists
ls -la $(pg_config --pkglibdir)/pg_ttl_index.so

# If missing, rebuild and install
make clean
make
sudo make install
```

### Extension Not Loading at Startup

**Error**: Extension functions not available after creating extension

**Solution**:
1. Verify `shared_preload_libraries` is set correctly:
   ```sql
   SHOW shared_preload_libraries;
   ```
2. Restart PostgreSQL server
3. Check PostgreSQL logs for errors

### Permission Denied

**Error**: `ERROR: permission denied to create extension`

**Solution**: You need superuser privileges:
```sql
-- Connect as superuser
psql -U postgres -d your_database_name

-- Or grant superuser temporarily
ALTER USER your_user SUPERUSER;
CREATE EXTENSION pg_ttl_index;
ALTER USER your_user NOSUPERUSER;
```

### Background Worker Not Starting

**Error**: `ttl_worker_status()` returns no rows

**Solutions**:
1. Verify extension is in `shared_preload_libraries`
2. Check `pg_ttl_index.enabled` is true:
   ```sql
   SHOW pg_ttl_index.enabled;
   ```
3. Manually start the worker:
   ```sql
   SELECT ttl_start_worker();
   ```

## Platform-Specific Notes

### Ubuntu/Debian

Install PostgreSQL development packages:
```bash
sudo apt-get update
sudo apt-get install postgresql-server-dev-16 build-essential
```

### CentOS/RHEL

```bash
sudo yum install postgresql16-devel gcc make
```

### macOS

```bash
# Install PostgreSQL via Homebrew
brew install postgresql@16

# Ensure development tools are available
xcode-select --install
```

### Windows

Windows support is experimental. Consider using WSL2 for development.

## Upgrading

### From v1.0.x to v2.0.0

:::danger Breaking Changes
Version 2.0.0 includes breaking changes to the `ttl_create_index()` function signature.
:::

See the [Migration Guide](advanced/migration.md) for detailed upgrade instructions.

## Next Steps

Now that the extension is installed:

1. **[Quick Start Guide](quick-start.md)** - Create your first TTL index
2. **[Configuration Guide](guides/configuration.md)** - Tune performance settings
3. **[API Reference](api/functions.md)** - Learn all available functions

## Getting Help

If you encounter issues:

- Check the [Troubleshooting Guide](advanced/troubleshooting.md)
- Review [GitHub Issues](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/issues)
- Ask questions in [GitHub Discussions](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/discussions)
