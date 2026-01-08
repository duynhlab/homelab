# PostgreSQL Custom Metrics Query Guide

## Overview

PostgreSQL clusters (Zalando operator) use `postgres_exporter` sidecars with custom queries to expose additional metrics beyond standard PostgreSQL metrics. This guide explains how to query these custom metrics in Prometheus.

## Naming Convention

postgres_exporter converts custom queries to Prometheus metrics using this pattern:

**Format**: `{query_name}_{column_name}`

**Example**:
- Query name: `pg_stat_statements`
- Column: `calls`
- Metric name: `pg_stat_statements_calls`

## Custom Metrics Available

### 1. pg_stat_statements Metrics

**Query Name**: `pg_stat_statements`  
**Purpose**: Query performance metrics (execution time, calls, cache hits, I/O statistics) - Top 100 queries

**Metrics Exposed**:

| Metric Name | Type | Description | Labels |
|------------|------|-------------|--------|
| `pg_stat_statements_calls` | COUNTER | Number of times executed | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_time_milliseconds` | COUNTER | Total time spent in the statement, in milliseconds | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_rows` | COUNTER | Total number of rows retrieved or affected | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_shared_blks_hit` | COUNTER | Total number of shared block cache hits | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_shared_blks_read` | COUNTER | Total number of shared blocks read | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_shared_blks_dirtied` | COUNTER | Total number of shared blocks dirtied | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_shared_blks_written` | COUNTER | Total number of shared blocks written | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_local_blks_hit` | COUNTER | Total number of local block cache hits | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_local_blks_read` | COUNTER | Total number of local blocks read | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_local_blks_dirtied` | COUNTER | Total number of local blocks dirtied | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_local_blks_written` | COUNTER | Total number of local blocks written | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_temp_blks_read` | COUNTER | Total number of temp blocks read | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_temp_blks_written` | COUNTER | Total number of temp blocks written | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_blk_read_time` | COUNTER | Total time spent reading blocks, in milliseconds | `user`, `datname`, `queryid`, `query` |
| `pg_stat_statements_blk_write_time` | COUNTER | Total time spent writing blocks, in milliseconds | `user`, `datname`, `queryid`, `query` |

**Labels**:
- `user`: The user who executed the statement
- `datname`: The database in which the statement was executed
- `queryid`: Internal hash code, computed from the statement's parse tree
- `query`: Processed query (truncated to 2000 characters)

**Query Details:**
- **Filtering**: Query excludes:
  - Queries containing `pg_stat_statements` (to avoid self-monitoring)
  - `postgres` database (system database)
  - `SET` statements
  - `COMMIT` and `BEGIN` statements
  - `SAVEPOINT` statements
- **Ordering**: Results ordered by `total_exec_time DESC LIMIT 100` (top 100 slowest queries)
- **Query Truncation**: Query text truncated to 2000 characters via `SUBSTRING()`
- **Join**: Joins with `pg_database` to get database name (`datname`)

### 2. pg_replication Metrics

**Query Name**: `pg_replication`  
**Purpose**: Replication lag monitoring (critical for HA clusters)

**Metrics Exposed**:

| Metric Name | Type | Description | Labels |
|------------|------|-------------|--------|
| `pg_replication_lag` | GAUGE | Replication lag behind master in seconds | (standard Prometheus labels: `instance`, `job`, `namespace`, etc.) |

**Note**: Returns 0 for primary/master, actual lag value for replicas

**Query Details:**
- **Query Logic**: 
  - If `pg_is_in_recovery() = false` (primary/master): Returns 0
  - If `pg_is_in_recovery() = true` (replica): Returns replication lag in seconds using `EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))`
- **master flag**: `master: true` - Query only runs on primary/master instance

### 3. pg_postmaster Metrics

**Query Name**: `pg_postmaster`  
**Purpose**: PostgreSQL server start time

**Metrics Exposed**:

| Metric Name | Type | Description | Labels |
|------------|------|-------------|--------|
| `pg_postmaster_start_time_seconds` | GAUGE | Time at which postmaster started (Unix timestamp) | (standard Prometheus labels) |

**Query Details:**
- **Function**: Uses `pg_postmaster_start_time()` to get PostgreSQL server start time
- **master flag**: `master: true` - Query only runs on primary/master instance
- **Use Case**: Calculate uptime with `time() - pg_postmaster_start_time_seconds`

## Configuration Reference

### Query Configuration Files

Custom queries are defined in ConfigMaps:
- **review-db**: `k8s/postgres-operator/zalando/monitoring-queries/postgres-monitoring-queries-review.yaml`
- **auth-db**: `k8s/postgres-operator/zalando/monitoring-queries/postgres-monitoring-queries-auth.yaml`
- **supporting-db**: `k8s/postgres-operator/zalando/monitoring-queries/postgres-monitoring-queries-supporting.yaml`

### Query Structure

Each query in `queries.yaml` follows this structure:

```yaml
query_name:
  query: "SELECT ..."
  master: true  # Optional: only run on primary/master
  metrics:
    - column_name:
        usage: "COUNTER|GAUGE|LABEL"
        description: "Description"
```

**Key Points:**
- `master: true` - Query only executes on primary/master PostgreSQL instance (important for HA clusters)
- `usage: "LABEL"` - Column becomes a label in Prometheus metrics
- `usage: "COUNTER"` - Column becomes a counter metric
- `usage: "GAUGE"` - Column becomes a gauge metric

## Querying in Prometheus

### Basic Queries

**1. List all custom metrics:**
```
{__name__=~"pg_stat_statements_.*|pg_replication_lag|pg_postmaster_start_time_seconds"}
```

**2. Query execution count per query:**
```
rate(pg_stat_statements_calls[5m])
```

**3. Query execution time (average per call):**
```
rate(pg_stat_statements_time_milliseconds[5m]) / rate(pg_stat_statements_calls[5m])
```

**4. Replication lag:**
```
pg_replication_lag
```

**5. PostgreSQL uptime:**
```
time() - pg_postmaster_start_time_seconds
```

### Filtered Queries

**1. Top 10 queries by execution count (review-db):**
```
topk(10, rate(pg_stat_statements_calls{namespace="review", datname="review"}[5m]))
```

**2. Top 10 slowest queries (auth-db):**
```
topk(10, rate(pg_stat_statements_time_milliseconds{namespace="auth", datname="auth"}[5m]) / rate(pg_stat_statements_calls{namespace="auth", datname="auth"}[5m]))
```

**3. Cache hit ratio per query:**
```
rate(pg_stat_statements_shared_blks_hit[5m]) / (rate(pg_stat_statements_shared_blks_hit[5m]) + rate(pg_stat_statements_shared_blks_read[5m]))
```

**4. Replication lag for HA clusters:**
```
pg_replication_lag{namespace="auth"}
```

**5. Query by specific queryid:**
```
pg_stat_statements_calls{queryid="1234567890"}
```

### Advanced Queries

**1. Total queries per second by database:**
```
sum(rate(pg_stat_statements_calls[5m])) by (datname, namespace)
```

**2. Average query execution time by database:**
```
sum(rate(pg_stat_statements_time_milliseconds[5m])) by (datname, namespace) / sum(rate(pg_stat_statements_calls[5m])) by (datname, namespace)
```

**3. I/O operations per second:**
```
sum(rate(pg_stat_statements_shared_blks_read[5m] + pg_stat_statements_shared_blks_written[5m])) by (datname, namespace)
```

**4. Replication lag alert (if > 10 seconds):**
```
pg_replication_lag > 10
```

## Verification

### Check if metrics are exposed

**1. Port-forward to postgres_exporter:**
```bash
kubectl port-forward -n review review-db-0 9187:9187
```

**2. Query metrics endpoint:**
```bash
curl http://localhost:9187/metrics | grep pg_stat_statements
curl http://localhost:9187/metrics | grep pg_replication
curl http://localhost:9187/metrics | grep pg_postmaster
```

### Check in Prometheus UI

**1. Access Prometheus:**
```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

**2. Query in Prometheus UI:**
- Go to: http://localhost:9090
- Enter query: `pg_stat_statements_calls`
- Check labels and values

### Check Prometheus targets

```bash
# Verify postgres_exporter is being scraped
kubectl get podmonitor -n review postgresql-review-db -o yaml

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Then visit: http://localhost:9090/targets
```

## Common Use Cases

### 1. Find Slow Queries

```promql
topk(10, 
  rate(pg_stat_statements_time_milliseconds{namespace="review"}[5m]) / 
  rate(pg_stat_statements_calls{namespace="review"}[5m])
)
```

### 2. Monitor Replication Health

```promql
# Replication lag
pg_replication_lag{namespace="auth"}

# Alert if lag > 10 seconds
pg_replication_lag{namespace="auth"} > 10
```

### 3. Track Query Performance Over Time

```promql
# Query execution rate
rate(pg_stat_statements_calls{queryid="1234567890"}[5m])

# Average execution time
rate(pg_stat_statements_time_milliseconds{queryid="1234567890"}[5m]) / 
rate(pg_stat_statements_calls{queryid="1234567890"}[5m])
```

### 4. Database I/O Statistics

```promql
# Cache hit ratio
sum(rate(pg_stat_statements_shared_blks_hit[5m])) by (datname) / 
(sum(rate(pg_stat_statements_shared_blks_hit[5m])) by (datname) + 
 sum(rate(pg_stat_statements_shared_blks_read[5m])) by (datname))
```

## Troubleshooting

### Metrics not appearing

**1. Check if ConfigMap is mounted:**
```bash
kubectl exec -n review review-db-0 -c exporter -- ls -la /etc/postgres-exporter/
kubectl exec -n review review-db-0 -c exporter -- cat /etc/postgres-exporter/queries.yaml
```

**2. Check environment variable:**
```bash
kubectl exec -n review review-db-0 -c exporter -- env | grep PG_EXPORTER_EXTEND_QUERY_PATH
```

**3. Check postgres_exporter logs:**
```bash
kubectl logs -n review review-db-0 -c exporter | grep -i error
```

**4. Verify pg_stat_statements is enabled:**
```bash
kubectl exec -n review review-db-0 -c postgres -- psql -U postgres -c "SHOW shared_preload_libraries;"
```

**5. Verify custom metrics are exposed:**
```bash
# Option 1: Direct exec into pod (recommended - no port-forward needed)
kubectl exec -n review review-db-0 -c exporter -- wget -qO- http://localhost:9187/metrics 2>&1 | head -5
kubectl exec -n review review-db-0 -c exporter -- wget -qO- http://localhost:9187/metrics 2>&1 | grep "^pg_stat_statements_calls" | head -3

# Option 2: Port-forward to postgres_exporter
kubectl port-forward -n review review-db-0 9187:9187 &

# Wait a few seconds, then query metrics
sleep 3
curl -s http://localhost:9187/metrics | grep -E "pg_stat_statements_calls|pg_replication_lag|pg_postmaster_start_time_seconds" | head -10

# Or check for any custom metrics
curl -s http://localhost:9187/metrics | grep "^pg_stat_statements\|^pg_replication\|^pg_postmaster"

# Stop port-forward when done
kill %1  # or pkill -f "kubectl port-forward"
```

**Expected output:**
- **Format Prometheus chuẩn**: `pg_stat_statements_calls{datname="review",query="...",queryid="...",server="localhost:5432",user="postgres"} 4`
- **Debug output** (có dấu `*`): Nếu thấy output dạng `* collected metric "pg_stat_statements_calls" {...} was collected before...` → đây là debug output từ Prometheus client, metrics vẫn hoạt động bình thường
- **HTTP 500 Error**: Nếu thấy HTTP 500 khi scrape → có thể do duplicate metrics. Đảm bảo `PG_EXPORTER_AUTO_DISCOVER_DATABASES` đã được xóa (deprecated và gây lỗi)
- **Nếu không có output**: Check logs for errors (step 3), verify ConfigMap mount (step 1), và environment variable (step 2)

### Metrics have wrong labels

- Check if Prometheus is applying relabel_configs correctly
- Verify PodMonitor configuration includes correct label selectors

## Related Documentation

- **Database Guide**: [`docs/guides/DATABASE.md`](../guides/DATABASE.md) - Custom queries configuration
- **Metrics Guide**: [`docs/monitoring/METRICS.md`](./METRICS.md) - General metrics documentation
- **Prometheus Guide**: [`docs/monitoring/PROMQL_GUIDE.md`](./PROMQL_GUIDE.md) - PromQL functions and examples
