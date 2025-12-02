# Distributed Tracing Guide

## Quick Summary

**Objectives:**
- Implement distributed tracing across microservices
- Propagate trace context using W3C Trace Context standard
- Correlate traces with logs and metrics

**Learning Outcomes:**
- Distributed tracing concepts and benefits
- W3C Trace Context propagation
- OpenTelemetry instrumentation
- Span creation and context propagation
- Trace-to-logs and trace-to-metrics correlation

**Keywords:**
Distributed Tracing, OpenTelemetry, Spans, Trace Context, W3C Trace Context, Trace-ID, OTLP, Tempo, Trace Propagation, Correlation

**Technologies:**
- OpenTelemetry (tracing standard)
- Grafana Tempo (trace storage)
- OTLP HTTP protocol
- W3C Trace Context headers

## Overview

Distributed tracing is implemented using **OpenTelemetry** and **Grafana Tempo**. All HTTP requests are automatically traced across microservices.

## How It Works

1. **Automatic Span Creation**: Every HTTP request creates a span
2. **Context Propagation**: Trace context is propagated via W3C Trace Context headers
3. **Span Attributes**: Service name, HTTP method, path, status code are automatically added
4. **Trace Storage**: Traces are sent to Tempo via OTLP HTTP protocol

## Trace-ID Propagation

### W3C Trace Context (Primary)

Traces use the W3C Trace Context standard with the `traceparent` header:

```
traceparent: 00-<trace-id>-<parent-id>-<flags>
```

### X-Trace-ID (Fallback)

If `traceparent` is not present, the system falls back to `X-Trace-ID` header.

### Automatic Generation

If no trace context is present, a new trace-id is automatically generated.

## Configuration

### Environment Variables

- `TEMPO_ENDPOINT`: Tempo OTLP HTTP endpoint (default: `http://tempo.monitoring.svc.cluster.local:4318`)
- `APP_NAME`: Service name (from Kubernetes pod label)
- `NAMESPACE`: Kubernetes namespace (from pod metadata)

### Service Initialization

```go
// Initialize OpenTelemetry tracing
tp, err := middleware.InitTracing()
if err != nil {
    logger.Warn("Failed to initialize tracing", zap.Error(err))
} else {
    defer func() {
        if err := tp.Shutdown(context.Background()); err != nil {
            logger.Error("Error shutting down tracer provider", zap.Error(err))
        }
    }()
}

// Add tracing middleware (must be first)
r.Use(middleware.TracingMiddleware())
```

## Manual Instrumentation

### Creating Child Spans

```go
import (
    "context"
    "github.com/duynhne/monitoring/pkg/middleware"
)

func handler(c *gin.Context) {
    ctx := c.Request.Context()
    
    // Create a child span
    ctx, span := middleware.StartSpan(ctx, "business-operation")
    defer span.End()
    
    // Your business logic here
    // ...
}
```

### Adding Span Attributes

```go
span.SetAttributes(
    attribute.String("user.id", userID),
    attribute.Int("order.count", orderCount),
)
```

### Adding Span Events

```go
span.AddEvent("order.created", trace.WithAttributes(
    attribute.String("order.id", orderID),
))
```

## Viewing Traces

### Grafana

1. Port-forward Grafana:
   ```bash
   kubectl port-forward -n monitoring svc/grafana 3000:3000
   ```

2. Open Grafana: http://localhost:3000

3. Navigate to **Explore** → Select **Tempo** datasource

4. Search traces by:
   - Service name
   - Operation name
   - Trace ID
   - Tags

### Tempo UI (Direct)

```bash
kubectl port-forward -n monitoring svc/tempo 3200:3200
# Open http://localhost:3200
```

## Trace-to-Logs Correlation

Traces are automatically correlated with logs via trace-id:

1. Open a trace in Grafana
2. Click on a span
3. View correlated logs in the **Logs** tab

## Trace-to-Metrics Correlation

Traces can be correlated with Prometheus metrics:

1. Open a trace in Grafana
2. Click on a span
3. View correlated metrics in the **Metrics** tab

## Best Practices

1. **Always propagate context**: When making HTTP calls to other services, ensure trace context is included
2. **Use meaningful span names**: Use descriptive names like "user.create" instead of "handler"
3. **Add business context**: Include relevant business attributes (user ID, order ID, etc.)
4. **Keep spans focused**: Create child spans for distinct operations
5. **Don't over-instrument**: Avoid creating spans for trivial operations

## Troubleshooting

### Traces not appearing

1. Check Tempo pod status:
   ```bash
   kubectl get pods -n monitoring -l app=tempo
   ```

2. Check Tempo logs:
   ```bash
   kubectl logs -n monitoring deployment/tempo
   ```

3. Verify service configuration:
   - Check `TEMPO_ENDPOINT` environment variable
   - Verify tracing middleware is added
   - Check service logs for initialization errors

### Trace context not propagating

1. Ensure tracing middleware is first in the middleware chain
2. Verify W3C Trace Context headers are being passed
3. Check service logs for trace-id in logs

## References

- [OpenTelemetry Go Documentation](https://opentelemetry.io/docs/instrumentation/go/)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [W3C Trace Context Specification](https://www.w3.org/TR/trace-context/)

