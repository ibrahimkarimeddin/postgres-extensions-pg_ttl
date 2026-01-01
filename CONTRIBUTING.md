# Contributing to pg_ttl_index

Thank you for your interest in contributing to pg_ttl_index! This document provides guidelines and instructions for contributing.

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started](#getting-started)
3. [Development Setup](#development-setup)
4. [Making Changes](#making-changes)
5. [Testing](#testing)
6. [Submitting Changes](#submitting-changes)
7. [Coding Standards](#coding-standards)

## Code of Conduct

This project adheres to a code of conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

**Be respectful, be collaborative, be helpful.**

## Getting Started

### Prerequisites

- PostgreSQL 12.0 or higher
- GCC or compatible C compiler
- GNU Make
- Git
- PostgreSQL development headers (`postgresql-server-dev-*`)

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/pg_ttl_index.git
   cd pg_ttl_index
   ```
3. Add the upstream repository:
   ```bash
   git remote add upstream https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl.git
   ```

## Development Setup

### Build the Extension

```bash
# Clean any previous builds
make clean

# Build the extension
make

# Install to your PostgreSQL installation
sudo make install
```

### Load the Extension

```sql
-- Connect to your test database
\c test_database

-- Create the extension
CREATE EXTENSION pg_ttl_index;

-- Start the worker
SELECT ttl_start_worker();
```

## Making Changes

### Branch Naming

Use descriptive branch names:
- `feature/add-new-function` - for new features
- `fix/issue-123` - for bug fixes
- `docs/update-readme` - for documentation
- `refactor/cleanup-worker` - for refactoring

### Commit Messages

Write clear, descriptive commit messages:

```
Short summary (50 chars or less)

More detailed explanatory text, if necessary. Wrap it to about 72
characters. The blank line separating the summary from the body is
critical.

- Bullet points are okay
- Use present tense ("Add feature" not "Added feature")
- Reference issues and pull requests

Fixes: #123
See also: #456
```

## Testing

### Running Tests

```bash
# Run regression tests (when implemented)
make installcheck

# Or run tests without installation
make check
```

### Manual Testing

Create a test script to verify your changes:

```sql
-- test/manual_test.sql
\c test_db

-- Create test table
CREATE TABLE test_table (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add TTL index
SELECT ttl_create_index('test_table', 'created_at', 60);

-- Insert test data
INSERT INTO test_table (data) VALUES ('test1'), ('test2');

-- Check TTL configuration
SELECT * FROM ttl_index_table;

-- Wait and verify cleanup (optional)
-- SELECT pg_sleep(65);
-- SELECT ttl_runner();
-- SELECT * FROM test_table;

-- Cleanup
SELECT ttl_drop_index('test_table', 'created_at');
DROP TABLE test_table;
```

### Test Coverage

When adding new features:
1. Add corresponding test cases
2. Verify edge cases
3. Test with different PostgreSQL versions (if possible)
4. Test with different data types (timestamp, timestamptz, date)

## Submitting Changes

### Before Submitting

1. **Update from upstream:**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Build and test:**
   ```bash
   make clean
   make
   sudo make install
   # Run your tests
   ```

3. **Check code style:**
   - Follow PostgreSQL C coding conventions
   - Use 4-space indentation (tabs in Makefile)
   - Add comments for complex logic
   - Keep lines under 80 characters when reasonable

4. **Update documentation:**
   - Update README.md if adding features
   - Update CHANGES file with your changes
   - Add inline code comments

### Pull Request Process

1. **Push to your fork:**
   ```bash
   git push origin feature/your-feature-name
   ```

2. **Create Pull Request:**
   - Go to GitHub and create a PR from your fork
   - Fill in the PR template with:
     - Description of changes
     - Related issues
     - Testing performed
     - Screenshots (if applicable)

3. **PR Title Format:**
   ```
   [TYPE] Brief description

   Examples:
   [FEATURE] Add support for interval-based TTL
   [FIX] Resolve worker crash on NULL timestamps
   [DOCS] Update installation instructions
   [REFACTOR] Improve error handling
   ```

4. **Address Review Comments:**
   - Respond to all review comments
   - Make requested changes
   - Push updates to the same branch

## Coding Standards

### C Code Standards

```c
/*
 * Function: my_function_name
 *
 * Description:
 *   Brief description of what this function does
 *
 * Parameters:
 *   param1 - description
 *   param2 - description
 *
 * Returns:
 *   Description of return value
 */
static bool
my_function_name(const char *param1, int param2)
{
    /* Variable declarations */
    StringInfoData query;
    bool result = false;

    /* Function body with clear logic */
    if (param1 == NULL)
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("param1 cannot be NULL")));

    /* More implementation */

    return result;
}
```

### SQL Code Standards

```sql
-- Use descriptive function/table names
-- Add comments for complex queries
-- Format for readability

CREATE OR REPLACE FUNCTION ttl_my_function(
    table_name TEXT,
    column_name TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    row_count INTEGER;
BEGIN
    -- Clear comment explaining the logic
    SELECT COUNT(*) INTO row_count
    FROM ttl_index_table
    WHERE table_name = $1
      AND column_name = $2;

    RETURN row_count > 0;
END;
$$;
```

### Documentation Standards

- Use Markdown for all documentation
- Keep README.md up to date
- Add examples for new features
- Document all parameters and return values
- Include error conditions

## Project Structure

```
pg_ttl_index/
├── src/                    # C source files
│   ├── pg_ttl_index.c      # Extension entry point
│   ├── worker.c            # Background worker logic
│   ├── api.c               # SQL interface implementation
│   └── utils.c             # Helper functions
├── test/                   # Regression tests
│   ├── sql/                # Test scripts
│   └── expected/           # Expected output
├── pg_ttl_index--*.sql     # SQL definitions
├── pg_ttl_index.control    # Extension control file
├── Makefile                # Build configuration
├── README.md               # User documentation
├── CONTRIBUTING.md         # This file
├── LICENSE                 # License information
├── CHANGES                 # Version history
└── META.json               # PGXN metadata
```


## Questions or Need Help?

- **GitHub Issues:** Open an issue for bugs or feature requests
- **Discussions:** Use GitHub Discussions for questions
- **Email:** Contact maintainers for security issues

## Recognition

Contributors will be acknowledged in:
- CHANGES file
- GitHub contributors list

Thank you for contributing to pg_ttl_index! 🎉
