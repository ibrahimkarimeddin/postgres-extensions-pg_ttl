# pg_ttl_index - PostgreSQL TTL Extension

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12%2B-blue.svg)](https://www.postgresql.org/)
[![License](https://img.shields.io/badge/License-PostgreSQL-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.2-green.svg)](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/releases)
[![Build Status](https://img.shields.io/github/actions/workflow/status/ibrahimkarimeddin/postgres-extensions-pg_ttl/ci.yml)](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/actions)

## 📋 Project Overview

`pg_ttl_index` is a professional PostgreSQL extension that provides automatic Time-To-Live (TTL) functionality for database tables. It automatically deletes expired data based on timestamp columns, helping you maintain clean databases without manual intervention.

### 🎯 Key Features

- ✅ **Automatic Data Expiration** - Set TTL once and let the extension handle the rest
- ✅ **Background Worker** - Efficient cleanup using PostgreSQL's background worker infrastructure
- ✅ **Multi-Table Support** - Configure different expiry times for multiple tables
- ✅ **Production Ready** - ACID compliant with SQL injection protection
- ✅ **Configurable** - Adjustable cleanup intervals and worker settings
- ✅ **Zero Downtime** - Minimal impact on application performance
- ✅ **PostgreSQL 12-16** - Compatible with modern PostgreSQL versions

## 📦 What's Included

This repository contains everything you need for professional PostgreSQL extension development:

### Core Files
- `pg_ttl_index.c` - Main C implementation with comprehensive documentation
- `pg_ttl_index--1.0.2.sql` - Latest SQL definitions
- `pg_ttl_index--1.0--1.0.2.sql` - Upgrade path from v1.0 to v1.0.2
- `pg_ttl_index.control` - Extension metadata
- `Makefile` - Professional build system with development targets

### Documentation
- `README.md` - Complete user guide with examples
- `QUICKSTART.md` - Developer quick start guide
- `CONTRIBUTING.md` - Contribution guidelines
- `SECURITY.md` - Security policy and best practices
- `LICENSE` - PostgreSQL open source license
- `CHANGES` - Version history

### Development Infrastructure
- `.gitignore` - Comprehensive ignore rules
- `.clang-format` - C code formatting configuration
- `.editorconfig` - Editor configuration for consistency
- `.github/workflows/ci.yml` - CI/CD pipeline for testing
- `test/test_ttl.sql` - Test suite
- `META.json` - PGXN (PostgreSQL Extension Network) metadata

## 🚀 Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl.git
cd pg_ttl_index

# Build and install
make
sudo make install

# Add to postgresql.conf
echo "shared_preload_libraries = 'pg_ttl_index'" | sudo tee -a /path/to/postgresql.conf

# Restart PostgreSQL
sudo systemctl restart postgresql
```

### Usage

```sql
-- Connect to your database
\c your_database

-- Create the extension
CREATE EXTENSION pg_ttl_index;

-- Start the background worker
SELECT ttl_start_worker();

-- Create a table with a timestamp column
CREATE TABLE sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    data JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Set TTL to 1 hour (3600 seconds)
SELECT ttl_create_index('sessions', 'created_at', 3600);

-- Monitor TTL status
SELECT * FROM ttl_summary();
```

## 📖 Documentation

- **[User Guide](README.md)** - Complete installation and usage guide
- **[Developer Guide](QUICKSTART.md)** - For contributors and developers
- **[Contributing](CONTRIBUTING.md)** - How to contribute
- **[Security Policy](SECURITY.md)** - Security considerations

## 🛠️ Development

### Build Commands

```bash
make              # Build the extension
make install      # Install to PostgreSQL
make clean        # Remove build artifacts
make dev          # Development build with extra warnings
make rebuild      # Clean, build, and install
make info         # Show extension information
make help         # Show all available targets
```

### Testing

```bash
# Run test suite
make installcheck

# Manual testing
psql -d test_db -f test/test_ttl.sql
```

## 🏗️ Project Structure

```
pg_ttl_index/
├── pg_ttl_index.c                 # Main C implementation
├── pg_ttl_index--1.0.2.sql        # Latest SQL definitions
├── pg_ttl_index--1.0.sql          # Previous version
├── pg_ttl_index--1.0--1.0.2.sql   # Upgrade script
├── pg_ttl_index.control           # Extension control file
├── Makefile                       # Build configuration
├── README.md                      # User documentation
├── QUICKSTART.md                  # Developer guide
├── CONTRIBUTING.md                # Contribution guidelines
├── SECURITY.md                    # Security policy
├── LICENSE                        # PostgreSQL license
├── CHANGES                        # Version history
├── META.json                      # PGXN metadata
├── .gitignore                     # Git ignore rules
├── .clang-format                  # Code formatting config
├── .editorconfig                  # Editor configuration
├── .github/
│   └── workflows/
│       └── ci.yml                 # CI/CD pipeline
└── test/
    └── test_ttl.sql              # Test suite
```

## 🔧 Configuration

### Background Worker Settings

```sql
-- Change cleanup interval (default: 60 seconds)
ALTER SYSTEM SET pg_ttl_index.naptime = 30;
SELECT pg_reload_conf();

-- Disable background worker
ALTER SYSTEM SET pg_ttl_index.enabled = false;
SELECT pg_reload_conf();
```

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Development setup
- Coding standards
- Testing guidelines
- Pull request process

## 🔒 Security

For security concerns, please see [SECURITY.md](SECURITY.md).

**Report vulnerabilities to:** ibrahimkarimeddin@gmail.com

## 📜 License

This project is licensed under the PostgreSQL License - see the [LICENSE](LICENSE) file for details.

## 👤 Author

**Ibrahim Karim Eddin**
- Email: ibrahimkarimeddin@gmail.com
- GitHub: [@ibrahimkarimeddin](https://github.com/ibrahimkarimeddin)

## 🙏 Acknowledgments

- PostgreSQL community for the extension infrastructure
- Contributors who have helped improve this extension

## 📊 Project Status

- **Version:** 1.0.2 (Stable)
- **Status:** Production Ready
- **PostgreSQL Compatibility:** 12, 13, 14, 15, 16
- **License:** PostgreSQL License
- **Maintenance:** Actively maintained

## 🔗 Links

- [GitHub Repository](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl)
- [Issue Tracker](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/issues)
- [PGXN (PostgreSQL Extension Network)](https://pgxn.org/)

---

**Made with ❤️ for the PostgreSQL community**
