# Jaeger Distributed Tracing Guide

## Overview

Jaeger is an open-source distributed tracing platform that runs alongside Grafana Tempo in this project. Both backends receive the same traces via OpenTelemetry Collector fan-out, giving you the flexibility to use either UI.

## Quick Start

### Access Jaeger UI

```bash
kubectl port-forward -n monitoring svc/jaeger-all-in-one 16686:16686
```

Open: http://localhost:16686

### Deploy Jaeger

```bash
./scripts/03d-deploy-jaeger.sh
```

## Jaeger vs Tempo Comparison

| Feature | Jaeger | Tempo |
|---------|--------|-------|
| **UI** | Standalone, feature-rich | Via Grafana |
| **Query Language** | Service + Tags | TraceQL (powerful) |
| **Service Graph** | Built-in dependency graph | Via metrics-generator |
| **Compare Traces** | Built-in compare feature | Not available |
| **Trace Timeline** | Detailed, expandable | Basic in Grafana |
| **Storage** | Memory, Badger, ES, Cassandra | Local, S3, GCS, Azure |
| **Resource Usage** | Higher (all-in-one) | Lower |
| **Best For** | Debugging, development | Production at scale |

## When to Use Jaeger

**Use Jaeger when:**
- You need a standalone tracing UI
- Debugging specific requests
- Comparing two traces side-by-side
- Viewing service dependency graph
- Familiar with Jaeger from other projects

**Use Tempo when:**
- Integrated Grafana experience
- Using TraceQL for complex queries
- Cost-effective storage at scale
- Correlating traces with metrics/logs in same UI

## Jaeger UI Features

### 1. Search Traces

**By Service:**
1. Select service from dropdown
2. Set time range
3. Click "Find Traces"

**By Tags:**
```
http.status_code=500
http.method=POST
user.id=123
```

**By Duration:**
- Min/Max duration filters
- Find slow requests

### 2. Trace Detail View

**Timeline View:**
- Expand/collapse spans
- View span details (tags, logs, process)
- See timing breakdown

**Span Information:**
- Operation name
- Duration
- Tags (http.method, http.url, etc.)
- Logs (events within span)
- Process info (service, hostname)

### 3. Compare Traces

1. Find first trace
2. Click "Compare" button
3. Search for second trace
4. Side-by-side comparison

**Use cases:**
- Compare slow vs fast requests
- Debug regression issues
- Analyze A/B differences

### 4. Service Dependencies

Navigate to "System Architecture" tab:
- Visual service dependency graph
- Request flow between services
- Identify critical paths

### 5. Deep Dependency Graph

Shows transitive dependencies:
- Direct dependencies
- Indirect dependencies
- Dependency depth

## Architecture in This Project

```mermaid
flowchart TB
    subgraph Apps["Microservices"]
        A1[auth]
        A2[user]
        A3[product]
    end
    
    subgraph OTelCollector["OTel Collector"]
        R[Receiver :4318]
        E1[Export to Tempo]
        E2[Export to Jaeger]
    end
    
    subgraph Backends
        Tempo[(Tempo<br/>Grafana query)]
        Jaeger[(Jaeger<br/>Standalone UI)]
    end
    
    Apps -->|OTLP| R
    R --> E1 --> Tempo
    R --> E2 --> Jaeger
```

**Key Points:**
- Applications send to OTel Collector (not Jaeger directly)
- Same traces appear in both Tempo and Jaeger
- No data duplication at application level

## Configuration

### Jaeger All-in-One

Located at: `k8s/jaeger/values.yaml`

```yaml
allInOne:
  enabled: true
  extraEnv:
    - name: COLLECTOR_OTLP_ENABLED
      value: "true"

storage:
  type: memory  # or badger for persistence
```

### Grafana Datasource

Located at: `k8s/grafana-operator/datasource-jaeger.yaml`

```yaml
datasource:
  name: Jaeger
  type: jaeger
  url: http://jaeger-all-in-one.monitoring.svc.cluster.local:16686
  jsonData:
    tracesToLogsV2:
      datasourceUid: loki
    tracesToMetrics:
      datasourceUid: prometheus
```

## Common Workflows

### Debug Slow Request

1. Open Jaeger UI
2. Select service
3. Set Min Duration (e.g., 500ms)
4. Find slow trace
5. Expand spans to find bottleneck
6. Check span tags for details

### Find Errors

1. Search with tag: `error=true`
2. Or: `http.status_code=500`
3. View trace timeline
4. Check span logs for error details

### Trace Cross-Service Request

1. Find trace by trace-id
2. View full timeline
3. See all services involved
4. Identify latency at each hop

### Compare Before/After

1. Find trace from before change
2. Copy trace ID
3. Find trace from after change
4. Use Compare feature
5. Analyze differences

## Troubleshooting

### No Traces in Jaeger

1. **Check Jaeger is running:**
   ```bash
   kubectl get pods -n monitoring -l app.kubernetes.io/name=jaeger
   ```

2. **Check OTel Collector:**
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=opentelemetry-collector
   ```

3. **Verify application endpoint:**
   ```bash
   kubectl exec -n auth deployment/auth -- env | grep OTEL_COLLECTOR_ENDPOINT
   # Should show: otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318
   ```

### Traces in Tempo but not Jaeger

1. **Check OTel Collector export to Jaeger:**
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=opentelemetry-collector | grep jaeger
   ```

2. **Verify Jaeger OTLP is enabled:**
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=jaeger | grep OTLP
   ```

### UI Shows "No Traces Found"

1. Extend time range
2. Check service name is correct
3. Generate some traffic first
4. Wait for traces to be indexed

## Best Practices

### 1. Use Meaningful Service Names

```yaml
# Good
OTEL_SERVICE_NAME: "order-service"

# Bad
OTEL_SERVICE_NAME: "app1"
```

### 2. Add Custom Tags

```go
span.SetAttributes(
    attribute.String("user.id", userID),
    attribute.String("order.id", orderID),
)
```

### 3. Use Span Events for Debugging

```go
span.AddEvent("cache_hit", trace.WithAttributes(
    attribute.String("key", cacheKey),
))
```

### 4. Set Meaningful Operation Names

```go
ctx, span := tracer.Start(ctx, "ProcessOrder")
// Not: tracer.Start(ctx, "handler")
```

## Related Documentation

- [APM Overview](./README.md)
- [Tracing Guide](./TRACING.md)
- [OTel Collector Config](../../k8s/otel-collector/README.md)
- [Jaeger Official Docs](https://www.jaegertracing.io/docs/)
