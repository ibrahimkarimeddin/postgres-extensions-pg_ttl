---
sidebar_position: 1
---

# Architecture & Internals

Understanding how `pg_ttl_index` works under the hood.

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   PostgreSQL Server                      │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │         Background Worker Process                   │ │
│  │  ┌──────────────────────────────────────────────┐  │ │
│  │  │  1. Wake up every naptime seconds           │  │ │
│  │  │  2. Try acquire advisory lock                │  │ │
│  │  │  3. Call ttl_runner()                        │  │ │
│  │  │  4. Sleep naptime seconds                    │  │ │
│  │  │  5. Repeat                                   │  │ │
│  │  └──────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────┘ │
│                          │                               │
│                          ▼                               │
│  ┌────────────────────────────────────────────────────┐ │
│  │              ttl_runner() Function                  │ │
│  │  ┌──────────────────────────────────────────────┐  │ │
│  │  │  FOR EACH active TTL in ttl_index_table      │  │ │
│  │  │    LOOP (batch deletion)                     │  │ │
│  │  │      DELETE batch_size rows WHERE expired    │  │ │
│  │  │      UPDATE statistics                       │  │ │
│  │  │      Sleep 10ms (yield to other processes)   │  │ │
│  │  │      EXIT when no more expired rows          │  │ │
│  │  │    END LOOP                                  │  │ │
│  │  │  END FOR                                     │  │ │
│  │  └──────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Components

### 1. Extension SQL Objects

**Location**: `pg_ttl_index--2.0.0.sql`

- **`ttl_index_table`** - Configuration and statistics storage
- **`ttl_create_index()`** - Create/update TTL rules
- **`ttl_drop_index()`** - Remove TTL rules  
- **`ttl_runner()`** - Execute cleanup logic
- **`ttl_summary()`** - View with computed fields
- **`ttl_worker_status()`** - Worker health information

###2. C Extension Layer

**Location**: `src/` directory

- **`pg_ttl_index.c`** - Extension initialization
- **`worker.c`** - Background worker implementation
- **`api.c`** - C functions (`ttl_start_worker`, `ttl_stop_worker`)
- **`utils.c`** - Helper utilities

### 3. Configuration

**Location**: `postgresql.conf`

- **`shared_preload_libraries`** - Load extension at startup
- **`pg_ttl_index.naptime`** - Cleanup interval (GUC)
- **`pg_ttl_index.enabled`** - Enable/disable worker (GUC)

## Background Worker Lifecycle

### Startup Sequence

```
1. PostgreSQL starts
   └─> Loads shared_preload_libraries
       └─> Loads pg_ttl_index.so
           └─> Registers background worker template

2. User calls ttl_start_worker()
   └─> Spawns background worker process
       └─> Worker connects to current database
           └─> Enters main loop
```

### Main Worker Loop

```c
while (true) {
    // 1. Check if shutdown requested
    if (shutdown_requested) break;
    
    // 2. Execute cleanup
    execute_sql("SELECT ttl_runner()");
    
    // 3. Sleep for naptime seconds
    sleep(pg_ttl_index_naptime);
}
```

### Shutdown Sequence

```
1. ttl_stop_worker() called
   └─> Signals worker to terminate
       └─> Worker exits main loop
           └─> Process terminates
```

## Cleanup Algorithm

### ttl_runner() Internals

```sql
1. Acquire advisory lock (pg_try_advisory_lock)
   └─> If already locked, exit (another instance running)

2. FOR EACH active TTL configuration:
   a. Initialize batch counter
   
   b. LOOP (until no more expired rows):
      i.   SELECT ctid of expired rows (LIMIT batch_size)
      ii.  DELETE rows with matching ctid
      iii. Update row counter
      iv.  Sleep 10ms (yield)
      v.   EXIT if deleted < batch_size
   
   c. UPDATE statistics (rows_deleted, last_run)
   d. COMMIT (per-table transaction)

3. Release advisory lock
4. RETURN total rows deleted
```

### Why ctid?

Using `ctid` (physical row location) is faster than index-based deletion:

```sql
-- Slow: requires index scan for each row
DELETE FROM table WHERE id IN (SELECT id FROM ...);

-- Fast: direct physical row access
DELETE FROM table WHERE ctid = ANY(ARRAY(SELECT ctid FROM ...));
```

## Concurrency Control

### Advisory Lock Mechanism

```sql
-- At start of ttl_runner()
SELECT pg_try_advisory_lock(hashtext('pg_ttl_index_runner'));

-- If lock acquired = true:
--   Proceed with cleanup
-- If lock acquired = false:
--   Another instance is running, skip this run
  
-- At end of ttl_runner()
SELECT pg_advisory_unlock(hashtext('pg_ttl_index_runner'));
```

**Benefits**:
- Prevents overlapping cleanup runs
- Safe in clustered/replica environments
- No database schema changes required

## Auto-Indexing

### Index Creation

When `ttl_create_index()` is called:

```sql
1. Generate index name: idx_ttl_{table}_{column}
2. Execute: CREATE INDEX IF NOT EXISTS idx_ttl_... ON table(column)
3. Store index name in ttl_index_table.index_name
```

**Example**:
```sql
SELECT ttl_create_index('sessions', 'created_at', 3600);
-- Creates: idx_ttl_sessions_created_at
```

### Index Usage

The index accelerates the expired row selection:

```sql
-- Without index: full table scan
SELECT ctid FROM table WHERE created_at < NOW() - INTERVAL '1 hour';

-- With index: index scan (much faster)
SELECT ctid FROM table WHERE created_at < NOW() - INTERVAL '1 hour';
```

## Batch Deletion Strategy

### Why Batching?

```
┌─────────────────────────────────────┐
│ Without Batching (delete all)       │
├─────────────────────────────────────┤
│ ❌ Long-running transactions        │
│ ❌ Locks table for extended period  │
│ ❌ Large WAL generation             │
│ ❌ bloat and performance issues     │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ With Batching (batch_size = 10K)    │
├─────────────────────────────────────┤
│ ✅ Short transactions                │
│ ✅ Minimal locking                   │
│ ✅ Manageable WAL size              │
│ ✅ Other queries can proceed        │
└─────────────────────────────────────┘
```

### Batch Processing Flow

```
Expired rows: 250,000
Batch size: 10,000

Iteration 1: Delete 10,000 rows → Sleep 10ms
Iteration 2: Delete 10,000 rows → Sleep 10ms
...
Iteration 25: Delete 10,000 rows → Sleep 10ms
Total: 250,000 rows deleted in 25 batches
```

## Statistics Tracking

### How Statistics are Updated

```sql
-- At end of each table's cleanup:
UPDATE ttl_index_table
SET 
    last_run = NOW(),
    rows_deleted_last_run = {rows deleted this run},
    total_rows_deleted = total_rows_deleted + {rows deleted this run}
WHERE table_name = ... AND column_name = ...;
```

### Counter Precision

- **`rows_deleted_last_run`**: BIGINT (max: 9,223,372,036,854,775,807)
- **`total_rows_deleted`**: BIGINT (will never overflow in practice)

## Error Handling

### Per-Table Isolation

```sql
FOR rec IN SELECT ... FROM ttl_index_table LOOP
    BEGIN
        -- Cleanup for this table
        ...
    EXCEPTION WHEN OTHERS THEN
        -- Log error, continue to next table
        RAISE WARNING 'Failed to cleanup %: %', rec.table_name, SQLERRM;
    END;
END LOOP;
```

**Result**: Error in one table doesn't affect others.

## Performance Characteristics

### Time Complexity

| Operation | Complexity | Notes |
|-----------|------------|-------|
| Create TTL index | O(n log n) | Index creation on existing table |
| Delete batch | O(batch_size) | With index |
| Find expired rows | O(log n) | Binary search via index |
| Update statistics | O(1) | Single row update |

### Space Complexity

- **ttl_index_table**: O(m) where m = number of TTL configurations (typically < 100)
- **Auto-created indexes**: O(n) per table, where n = table size

### Resource Usage

**Per cleanup run**:
- CPU: Minimal (index lookups + deletes)
- Memory: ~10-50 MB (batch processing)
- I/O: Proportional to deleted rows
- WAL: ~(row_size × rows_deleted)

## Comparison with Alternatives

### vs. Triggers

| Feature | pg_ttl_index | Triggers |
|---------|--------------|----------|
| Performance | ✅ Batch deletion | ❌ Per-row overhead |
| Complexity | ✅ Simple setup | ❌ Complex trigger logic |
| Control | ✅ Centralized | ❌ Spread across tables |

### vs. CRON Jobs

| Feature | pg_ttl_index | CRON |
|---------|--------------|------|
| Integration | ✅ Native PostgreSQL | ❌ External dependency |
| Monitoring | ✅ Built-in views | ❌ Custom logging |
| Concurrency | ✅ Advisory locks | ❌ Manual coordination |

### vs. Partitioning

| Feature | pg_ttl_index | Partitioning |
|---------|--------------|--------------|
| Granularity | ✅ Row-level | ❌ Partition-level |
| Setup | ✅ Simple function call | ❌ Complex schema changes |
| Flexibility | ✅ Change TTL anytime | ❌ Requires repartitioning |

## Internal Functions (Not Public API)

These functions exist but are not meant for direct use:

- `pg_ttl_index_main()` - Worker main loop (C)
- `ttl_worker_launch()` - Internal worker launcher (C)

## Source Code Organization

```
src/
├── pg_ttl_index.c     # Extension initialization, _PG_init()
├── pg_ttl_index.h     # Header file, constants
├── worker.c           # Background worker implementation
├── api.c              # Public C functions (start/stop worker)
├── utils.c            # Helper functions
└── utils.h            # Helper headers
```

## See Also

- [Performance Guide](performance.md) - Optimization strategies
- [API Reference](../api/functions.md) - Public functions
- [Source Code](https://github.com/ibrahimkarimeddin/postgres-extensions-pg_ttl) - GitHub repository
