# Structured Logging Guide

## Quick Summary

**Objectives:**
- Implement structured JSON logging with trace-id correlation
- Configure Vector for log collection and Loki for log storage
- Query and correlate logs with traces in Grafana

**Learning Outcomes:**
- Structured logging best practices with Zap
- Trace-ID propagation and correlation
- LogQL query syntax for Loki
- Vector log collection and transformation
- Log-to-trace correlation patterns

**Keywords:**
Structured Logging, JSON Logs, Trace-ID, Log Correlation, LogQL, Log Aggregation, Vector, Loki, Zap Logger, Log Levels, Log Queries

**Technologies:**
- Zap (Go structured logger)
- Vector (log collection agent)
- Loki (log storage and querying)
- Grafana (log visualization)

## Overview

All services use **structured JSON logging** with **trace-id correlation**. Logs are collected by **Vector** and stored in **Loki**.

## Log Format

All logs are in JSON format with the following structure:

```json
{
  "timestamp": "2024-01-15T10:30:45.123Z",
  "level": "info",
  "message": "HTTP request",
  "trace_id": "abc123def456",
  "method": "GET",
  "path": "/api/v1/users",
  "status": 200,
  "duration": 0.045,
  "client_ip": "10.0.0.1",
  "user_agent": "Mozilla/5.0...",
  "caller": "middleware/logging.go:123"
}
```

## Trace-ID in Logs

Every log entry includes a `trace_id` field that:
- Links logs to distributed traces
- Enables log-to-trace correlation in Grafana
- Allows searching logs by trace-id

## Log Levels

- **INFO**: Normal operations (HTTP requests, successful operations)
- **WARN**: Warning conditions (failed tracing initialization, etc.)
- **ERROR**: Error conditions (HTTP errors, failed operations)
- **FATAL**: Critical errors (server startup failures)

## Automatic Logging

### HTTP Request Logging

All HTTP requests are automatically logged with:
- Method, path, status code
- Request duration
- Client IP and user agent
- Trace ID

### Error Logging

HTTP errors (4xx, 5xx) are automatically logged at ERROR level.

## Manual Logging

### Using Logger from Context

```go
import (
    "github.com/duynhlab/monitoring/pkg/middleware"
    "go.uber.org/zap"
)

func handler(c *gin.Context) {
    logger := middleware.GetLoggerFromContext(c, baseLogger)
    
    logger.Info("Processing order",
        zap.String("order_id", orderID),
        zap.String("user_id", userID),
    )
}
```

### Adding Custom Fields

```go
logger.Info("User created",
    zap.String("user_id", userID),
    zap.String("email", email),
    zap.Int("age", age),
)
```

## Log Collection

### Vector Configuration

Vector collects logs from all pods and:
1. Parses JSON logs
2. Extracts trace-id
3. Adds service name and namespace labels
4. Sends to Loki

### Loki Storage

Logs are stored in Loki with labels:
- `service`: Service name
- `namespace`: Kubernetes namespace
- `pod`: Pod name
- `container`: Container name
- `trace_id`: Trace ID (for correlation)

## Viewing Logs

### Grafana

1. Port-forward Grafana:
   ```bash
   kubectl port-forward -n monitoring svc/grafana-service 3000:3000
   ```

2. Open Grafana: http://localhost:3000

3. Navigate to **Explore** → Select **Loki** datasource

4. Query logs:
   ```
   {service="auth"} |= "error"
   {trace_id="abc123"}
   {namespace="auth"} | json | level="error"
   ```

### Log-to-Trace Correlation

1. Open a trace in Grafana (Tempo datasource)
2. Click on a span
3. View correlated logs in the **Logs** tab

### Trace-to-Log Correlation

1. Open logs in Grafana (Loki datasource)
2. Click on a log entry with trace_id
3. Click "Query with Tempo" to view the trace

## Grafana Logs Drilldown

**Available in**: Grafana 11.6+ (you have 12.1.4) with Loki v3.2+ (you have 3.6.2)

Grafana Logs Drilldown uses **pattern ingestion** and **level detection** to automatically analyze log patterns and identify common structures in your logs.

### Features

1. **Pattern Detection**: Automatically identifies recurring log patterns
2. **Level Detection**: Automatically detects log levels (INFO, WARN, ERROR, etc.)
3. **Volume Queries**: Query log volumes for capacity planning

### Usage

1. Navigate to **Explore** in Grafana
2. Select **Loki** datasource
3. Use the **Patterns** tab (new in Grafana 11.6+)
4. Loki will show detected patterns and frequencies

### Example Queries

**Pattern analysis**:
```logql
{service="auth"} | pattern "<timestamp> <level> <message>"
```

**Volume queries** (enabled by `volume_enabled: true`):
```logql
sum by (service) (count_over_time({namespace="auth"}[5m]))
```

**Level detection** (automatic with `discover_log_levels: true`):
```logql
{service="auth", detected_level="error"}
```

### Configuration

Pattern ingestion and level detection are enabled via:

**Loki config:**
- `--pattern-ingester.enabled=true` - Enable pattern detection
- `--validation.discover-log-levels=true` - Enable log level detection
- `discover_log_levels: true` in `limits_config`

**Vector config:**
- JSON parsing in `add_labels` transform - Extracts `level` field from structured log messages
- Automatically promotes `level` from nested JSON to top-level field for Loki detection

## Vector Monitoring

Vector exports internal metrics about its own performance to Prometheus. This allows you to monitor the health and performance of the logging pipeline.

### Available Metrics

Key Vector metrics available in Prometheus:

- **`vector_events_processed_total`** - Total events processed by each component
- **`vector_component_errors_total`** - Total errors by component  
- **`vector_component_sent_bytes_total`** - Bytes sent to sinks (e.g. Loki)
- **`vector_component_received_bytes_total`** - Bytes received from sources
- **`vector_buffer_events`** - Events currently in buffer
- **`vector_utilization`** - Component utilization (0.0-1.0)

### Querying Vector Metrics

**Check Vector health**:
```promql
up{job="vector"}
```

**Events processed per second**:
```promql
rate(vector_events_processed_total[5m])
```

**Error rate**:
```promql
rate(vector_component_errors_total[5m])
```

**Loki sink throughput** (bytes/sec):
```promql
rate(vector_component_sent_bytes_total{component_name="loki"}[5m])
```

**Buffer utilization**:
```promql
vector_buffer_events
```

### Monitoring Vector in Grafana

**Option 1: Pre-built Dashboard** (Recommended)

1. Navigate to **Dashboards** in Grafana
2. Open the **Vector** dashboard (imported from Grafana.com ID: 21954)
3. View comprehensive Vector metrics:
   - Events per second by component
   - Component error rates
   - Buffer utilization
   - Throughput (bytes/sec)
   - Component health status

**Option 2: Manual Queries via Explore**

1. Navigate to **Explore** in Grafana
2. Select **Prometheus** datasource
3. Query Vector metrics (namespace: `vector_*`)

**Recommended Alerts**:
- High error rate: `rate(vector_component_errors_total[5m]) > 10`
- Buffer overflow: `vector_buffer_events > 10000`
- Low throughput: `rate(vector_events_processed_total[5m]) < 100`

### Configuration

Vector self-monitoring is configured via:
- **Source**: `internal_metrics` (collects Vector's internal metrics)
- **Sink**: `prometheus_exporter` (exposes metrics on port 9090)
- **ServiceMonitor**: Automatic Prometheus scraping (30s interval)

## Log Queries

### By Service

```
{service="auth"}
```

### By Trace ID

```
{trace_id="abc123def456"}
```

### By Log Level

```
{service="auth"} | json | level="error"
```

### By Time Range

```
{service="auth"} [5m]
```

### Text Search

```
{service="auth"} |= "login"
```

### JSON Field Filtering

```
{service="auth"} | json | status=500
```

## Best Practices

1. **Use structured fields**: Always use zap fields instead of string formatting
2. **Include context**: Add relevant business context (user ID, order ID, etc.)
3. **Don't log sensitive data**: Never log passwords, tokens, or PII
4. **Use appropriate levels**: Use ERROR for errors, INFO for normal operations
5. **Keep messages concise**: Use short, descriptive messages

## Troubleshooting

### Logs not appearing in Loki

1. Check Vector pods:
   ```bash
   kubectl get pods -n kube-system -l app=vector
   ```

2. Check Vector logs:
   ```bash
   kubectl logs -n kube-system -l app=vector
   ```

3. Check Loki status:
   ```bash
   kubectl get pods -n monitoring -l app=loki
   ```

4. Verify log format: Ensure logs are in JSON format

### Trace-ID missing in logs

1. Verify logging middleware is added
2. Check that trace context is being propagated
3. Verify trace-id is being extracted correctly

## References

- [Zap Logger Documentation](https://github.com/uber-go/zap)
- [Loki Query Documentation](https://grafana.com/docs/loki/latest/logql/)
- [Vector Documentation](https://vector.dev/docs/)

