---
sidebar_position: 3
---

# Contributing

Help improve `pg_ttl_index`! Contributions are welcome.

## Ways to Contribute

- 🐛 **Report bugs** - Found an issue? Let us know!
- ✨ **Suggest features** - Have ideas? Share them!
- 📝 **Improve documentation** - Fix typos, add examples
- 💻 **Submit code** - Fix bugs, add features
- 🧪 **Write tests** - Improve test coverage
- 📣 **Spread the word** - Share with others

## Reporting Bugs

### Before Reporting

1. Check [existing issues](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/issues)
2. Try the latest version
3. Review [Troubleshooting Guide](advanced/troubleshooting.md)

### What to Include

```markdown
**Environment**:
- PostgreSQL version: 16.1
- pg_ttl_index version: 2.0.0
- Operating System: Ubuntu 22.04

**Description**:
Clear description of the problem

**Steps to Reproduce**:
1. Create table...
2. Run SELECT ttl_create_index(...)
3. Observe error...

**Expected Behavior**:
What should happen

**Actual Behavior**:
What actually happened

**Logs**:
```sql
-- Relevant PostgreSQL logs
```

**Additional Context**:
Any other information
```

[Report a Bug](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/issues/new)

## Suggesting Features

### Feature Request Template

```markdown
**Feature Description**:
Brief summary of the feature

**Use Case**:
Why is this needed? What problem does it solve?

**Proposed Solution**:
How should it work?

**Alternatives Considered**:
Other approaches you've thought about

**Additional Context**:
Mockups, examples, etc.
```

[Request a Feature](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/issues/new)

## Development Setup

### Prerequisites

- PostgreSQL 12+ development packages
- GCC or Clang compiler
- Make
- Git

### Clone & Build

```bash
# Clone repository
git clone https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl.git
cd postgres-extensions-pg_ttl

# Build extension
make

# Install locally
sudo make install

# Run tests
make installcheck
```

### Development Workflow

```bash
# Create feature branch
git checkout -b feature/your-feature-name

# Make changes
$EDITOR src/worker.c

# Build
make clean && make

# Test
make installcheck

# Commit
git add .
git commit -m "feat: add your feature"

# Push
git push origin feature/your-feature-name
```

## Code Style

### C Code

Follow PostgreSQL coding conventions:

```c
// Good
static void
cleanup_expired_rows(char *table_name)
{
    /* Clear documentation */
    int     rows_deleted = 0;
    
    /* Code here */
}

// Bad
static void cleanupExpiredRows(char* tableName) {
    int rowsDeleted=0;
}
```

**Key points**:
- Tabs (not spaces) for indentation
- Opening brace on same line for functions
- Use PostgreSQL data types (`int32`, `Datum`, etc.)
- Document with `/* */` comments

### SQL Code

```sql
-- Good: clear, formatted
CREATE OR REPLACE FUNCTION ttl_runner()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT ... LOOP
        -- Code
    END LOOP;
    
    RETURN total;
END;
$$;

-- Bad: cramped, unclear
CREATE FUNCTION ttl_runner() RETURNS INTEGER LANGUAGE plpgsql AS $$ BEGIN FOR rec IN SELECT ... LOOP END LOOP; RETURN total; END;$$;
```

### Format Your Code

```bash
# Format C code (if clang-format available)
make format

# Check SQL syntax
psql -d test -f pg_ttl_index--2.0.0.sql
```

## Testing

### Run Regression Tests

```bash
# Full test suite
make installcheck

# Results in: regression.diffs (if any failures)
```

### Add New Tests

Edit `test/sql/pg_ttl_index_test.sql`:

```sql
-- Test your feature
CREATE TABLE test_feature (...);
SELECT ttl_create_index('test_feature', 'created_at', 60);

-- Verify expected behavior
SELECT * FROM ttl_summary() WHERE table_name = 'test_feature';

-- Cleanup
SELECT ttl_drop_index('test_feature', 'created_at');
DROP TABLE test_feature;
```

Expected output in `test/expected/pg_ttl_index_test.out`.

### Manual Testing

```bash
# Start test database
docker-compose up -d

# Connect
psql -h localhost -U postgres -d postgres

# Test your changes
CREATE EXTENSION pg_ttl_index;
SELECT ttl_start_worker();
-- Test...
```

## Submitting Pull Requests

### Before Submitting

- ✅ Tests pass (`make installcheck`)
- ✅ Code follows style guide
- ✅ Documentation updated (if needed)
- ✅ Commit messages are clear
- ✅ Branch is up to date with `main`

### Pull Request Template

```markdown
## Description
Brief description of changes

## Motivation
Why is this change needed?

## Changes Made
- Added feature X
- Fixed bug Y
- Updated documentation Z

## Testing
How did you test this?

## Checklist
- [ ] Tests pass
- [ ] Documentation updated
- [ ] Code follows style guide
- [ ] Tested on PostgreSQL 12, 13, 14, 15, 16 (if applicable)
```

### Commit Message Format

```
type(scope): brief description

Longer explanation if needed

Fixes #123
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `test`: Adding tests
- `refactor`: Code refactoring
- `perf`: Performance improvement

**Examples**:
```
feat(worker): add batch deletion support

fix(api): handle missing timestamp column gracefully

docs(readme): update installation instructions
```

## Documentation

### Building Docs Locally

```bash
cd website_docs
npm install
npm start
```

Visit http://localhost:3000

### Writing Documentation

- Use clear, concise language
- Include code examples
- Add cross-links between related pages
- Test all SQL examples

## Code Review Process

1. **Automated checks** run (tests, linting)
2. **Maintainer review** (usually within 1 week)
3. **Feedback & iteration** (if needed)
4. **Approval & merge**

## Community Guidelines

- Be respectful and constructive
- Welcome newcomers
- Focus on ideas, not people
- Assume good intentions

## License

By contributing, you agree that your contributions will be licensed under the PostgreSQL License.

## Questions?

- **GitHub Discussions**: [Ask questions](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/discussions)
- **Email**: ibrahimkarimeddin@gmail.com

## Thank You!

Every contribution helps make `pg_ttl_index` better. Thank you for your time and effort!

## See Also

- [Architecture Guide](advanced/architecture.md) - Understanding internals
- [Development Guide](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl/blob/main/CONTRIBUTING.md) - Detailed development docs
