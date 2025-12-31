# Development Quickstart

This guide is for developers who want to quickly get started with pg_ttl_index development.

## Prerequisites

```bash
# macOS
brew install postgresql

# Ubuntu/Debian
sudo apt-get install postgresql-server-dev-14 postgresql-14

# Verify installation
pg_config --version
```

## Quick Setup

```bash
# Clone the repository
git clone https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl.git
cd pg_ttl_index

# Build and install
make clean
make
sudo make install

# Connect to PostgreSQL
psql -d your_test_database

# In psql:
CREATE EXTENSION pg_ttl_index;
SELECT ttl_start_worker();
```

## Development Workflow

```bash
# 1. Make changes to pg_ttl_index.c or SQL files

# 2. Rebuild and reinstall
make rebuild

# 3. Test in psql
psql -d test_db

# In psql, reload the extension:
DROP EXTENSION pg_ttl_index CASCADE;
CREATE EXTENSION pg_ttl_index;
SELECT ttl_start_worker();

# 4. Run tests
make installcheck
```

## Common Development Tasks

### View Extension Info
```bash
make info
```

### Development Build (with extra warnings)
```bash
make dev
```

### Format Code
```bash
make format
```

### Create Distribution Package
```bash
make dist
```

## Testing

### Manual Testing
```sql
-- Create a test table
CREATE TABLE test_data (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add TTL (1 minute)
SELECT ttl_create_index('test_data', 'created_at', 60);

-- Insert old data
INSERT INTO test_data (created_at) VALUES (NOW() - INTERVAL '2 minutes');
INSERT INTO test_data (created_at) VALUES (NOW());

-- Check before cleanup
SELECT COUNT(*) FROM test_data;

-- Run cleanup
SELECT ttl_runner();

-- Check after cleanup (should be 1 row)
SELECT COUNT(*) FROM test_data;

-- Cleanup
SELECT ttl_drop_index('test_data', 'created_at');
DROP TABLE test_data;
```

### Background Worker Testing
```sql
-- Start worker
SELECT ttl_start_worker();

-- Check worker status
SELECT * FROM ttl_worker_status();

-- Check from pg_stat_activity
SELECT pid, application_name, state 
FROM pg_stat_activity 
WHERE application_name LIKE '%TTL%';

-- Stop worker
SELECT ttl_stop_worker();
```

## Debugging

### Enable PostgreSQL Logging
```bash
# Edit postgresql.conf
log_min_messages = debug1
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
```

### View Logs
```bash
# macOS (Homebrew)
tail -f /opt/homebrew/var/log/postgres.log

# Linux
sudo tail -f /var/log/postgresql/postgresql-14-main.log
```

### Debug Worker Issues
```sql
-- Check if worker is running
SELECT * FROM pg_stat_activity WHERE application_name LIKE '%TTL%';

-- Check configuration
SELECT name, setting FROM pg_settings WHERE name LIKE 'pg_ttl%';

-- Check last run times
SELECT * FROM ttl_summary();
```

## Project Structure

```
pg_ttl_index/
├── pg_ttl_index.c              # Main C implementation
├── pg_ttl_index--1.0.2.sql     # Current version SQL
├── pg_ttl_index--1.0.sql       # Previous version SQL
├── pg_ttl_index--1.0--1.0.2.sql # Upgrade script
├── pg_ttl_index.control        # Extension metadata
├── Makefile                    # Build configuration
├── README.md                   # User documentation
├── CONTRIBUTING.md             # Contribution guidelines
├── QUICKSTART.md              # This file
├── LICENSE                     # License information
└── test/                      # Test files
    └── test_ttl.sql
```

## Tips

1. **Always rebuild after C changes:** `make rebuild`
2. **Test with multiple PostgreSQL versions:** Use Docker containers
3. **Write tests for new features:** Add to `test/test_ttl.sql`
4. **Update documentation:** Keep README.md current
5. **Follow PostgreSQL coding style:** See CONTRIBUTING.md

## Common Issues

### Extension Won't Load
```bash
# Check if files are installed
ls -la $(pg_config --sharedir)/extension/pg_ttl*
ls -la $(pg_config --pkglibdir)/pg_ttl*

# Reinstall
sudo make install
```

### Background Worker Won't Start
```sql
-- Check shared_preload_libraries
SHOW shared_preload_libraries;

-- If pg_ttl_index is not listed, add it to postgresql.conf:
-- shared_preload_libraries = 'pg_ttl_index'
-- Then restart PostgreSQL
```

### Compilation Errors
```bash
# Make sure you have PostgreSQL development headers
dpkg -l | grep postgresql-server-dev  # Debian/Ubuntu
brew list | grep postgresql            # macOS

# Check pg_config path
which pg_config
pg_config --version
```

## Next Steps

- Read the full [README.md](README.md)
- Check [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines
- Review the C code in `pg_ttl_index.c`
- Write tests in `test/test_ttl.sql`

Happy coding! 🚀
