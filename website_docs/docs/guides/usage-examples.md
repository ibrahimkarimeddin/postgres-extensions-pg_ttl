---
sidebar_position: 2
---

# Usage Examples

Real-world examples of using `pg_ttl_index` in various scenarios.

## Session Management

### Web Application Sessions

```sql
-- Create sessions table
CREATE TABLE user_sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER NOT NULL,
    ip_address INET,
    user_agent TEXT,
    session_data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_activity TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for user lookups
CREATE INDEX idx_user_sessions_user_id ON user_sessions(user_id);

-- TTL: expire sessions after 30 minutes of inactivity
SELECT ttl_create_index('user_sessions', 'last_activity', 1800);
```

### API Token Expiration

```sql
-- API tokens with expiration
CREATE TABLE api_tokens (
    token_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER NOT NULL,
    token_hash TEXT NOT NULL,
    scopes TEXT[],
   created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);

-- TTL: clean up immediately when expired
SELECT ttl_create_index('api_tokens', 'expires_at', 0);
```

## Log Management

### Application Logs

```sql
-- Centralized application logs
CREATE TABLE app_logs (
    id BIGSERIAL PRIMARY KEY,
    service_name VARCHAR(100) NOT NULL,
    level VARCHAR(10) NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Partition by service for better performance
CREATE INDEX idx_app_logs_service ON app_logs(service_name);

-- TTL: keep logs for 7 days
SELECT ttl_create_index('app_logs', 'logged_at', 604800, 50000);
```

### Audit Trail

```sql
-- Compliance audit log
CREATE TABLE audit_trail (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    action VARCHAR(50) NOT NULL,
    resource_type VARCHAR(50),
    resource_id INTEGER,
    details JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- TTL: retain for 90 days (compliance requirement)
SELECT ttl_create_index('audit_trail', 'created_at', 7776000, 25000);
```

## Cache Management

### Application Cache

```sql
-- Simple key-value cache
CREATE TABLE cache_entries (
    cache_key VARCHAR(255) PRIMARY KEY,
    cache_value TEXT NOT NULL,
    tags TEXT[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);

-- TTL: respect expires_at column
SELECT ttl_create_index('cache_entries', 'expires_at', 0, 10000);
```

### Query Result Cache

```sql
-- Cache expensive query results
CREATE TABLE query_cache (
    query_hash VARCHAR(64) PRIMARY KEY,
    query_sql TEXT NOT NULL,
    result_data JSONB NOT NULL,
    cached_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- TTL: invalidate cache after 1 hour
SELECT ttl_create_index('query_cache', 'cached_at', 3600);
```

## Analytics & Metrics

### Event Tracking

```sql
-- User events for analytics
CREATE TABLE user_events (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER,
    event_type VARCHAR(50) NOT NULL,
    properties JSONB,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Partition by date for better performance
CREATE INDEX idx_user_events_timestamp ON user_events(timestamp);

-- TTL: raw events kept for 24 hours
SELECT ttl_create_index('user_events', 'timestamp', 86400, 100000);
```

### Time-Series Metrics

```sql
-- Metrics collected every second
CREATE TABLE system_metrics (
    id BIGSERIAL PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL,
    metric_value NUMERIC NOT NULL,
    tags JSONB,
    collected_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- TTL: keep raw metrics for 6 hours
SELECT ttl_create_index('system_metrics', 'collected_at', 21600, 100000);
```

## E-Commerce

### Shopping Carts

```sql
-- Abandoned cart management
CREATE TABLE shopping_carts (
    cart_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER,
    session_id TEXT,
    items JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- TTL: abandon carts after 24 hours of inactivity
SELECT ttl_create_index('shopping_carts', 'updated_at', 86400);
```

### Price History

```sql
-- Track price changes over time
CREATE TABLE price_history (
    id BIGSERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- TTL: keep price history for 30 days
SELECT ttl_create_index('price_history', 'recorded_at', 2592000, 50000);
```

## Job Queues

### Background Jobs

```sql
-- Job queue with automatic cleanup
CREATE TABLE background_jobs (
    job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_type VARCHAR(50) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- TTL: clean up completed jobs after 7 days
SELECT ttl_create_index('background_jobs', 'completed_at', 604800);
```

## Notifications

### User Notifications

```sql
-- In-app notifications
CREATE TABLE notifications (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_id ON notifications(user_id);

-- TTL: delete read notifications after 30 days
SELECT ttl_create_index('notifications', 'created_at', 2592000);
```

## Rate Limiting

### API Rate Limit Tracking

```sql
-- Track API requests for rate limiting
CREATE TABLE api_rate_limits (
    id BIGSERIAL PRIMARY KEY,
    api_key VARCHAR(64) NOT NULL,
    endpoint VARCHAR(255) NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 1,
    window_start TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rate_limits ON api_rate_limits(api_key, endpoint, window_start);

-- TTL: sliding window of 1 hour
SELECT ttl_create_index('api_rate_limits', 'window_start', 3600, 50000);
```

## Multi-Tenant Setup

```sql
-- Different TTL per tenant
CREATE TABLE tenant_data (
    id BIGSERIAL PRIMARY KEY,
    tenant_id INTEGER NOT NULL,
    data_type VARCHAR(50) NOT NULL,
    data JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tenant A: 7 days retention
CREATE VIEW tenant_a_data AS 
SELECT * FROM tenant_data WHERE tenant_id = 1;

SELECT ttl_create_index('tenant_data', 'created_at', 604800);

-- Note: Use partitioning for true per-tenant TTL
```

## See Also

- [Best Practices](best-practices.md) - Optimization tips
- [Monitoring](monitoring.md) - Track cleanup effectiveness
- [API Reference](../api/functions.md) - Function documentation
