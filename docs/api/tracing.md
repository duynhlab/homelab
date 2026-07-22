# Application Tracing

Distributed tracing contract for all ten Go microservices and both workers — sampling, span helpers, propagation, and best practices.

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **SDK** | `obsx.SetupObservability()` — one call in `main()` | — |
| **Propagation** | W3C Trace Context (`traceparent`); Kong injects at edge | — |
| **Sampling** | `ParentBased(TraceIDRatioBased)` — root decides, downstream honours | — |
| **Platform backends** | [Tracing (platform)](../observability/tracing/README.md) — Tempo, Jaeger, VictoriaTraces | — |
| **Cross-cutting** | [Application observability](./observability.md) | — |
| **Design record** | — | [RFC-0014](../proposals/rfc/RFC-0014/) |

---

## Configuration

Tracing env vars are injected by app ResourceSets (`kubernetes/apps/domains/*-rs.yaml`, workers):

```yaml
env:
  - name: OTEL_COLLECTOR_ENDPOINT
    value: otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318
  - name: OTEL_SAMPLE_RATE
    value: "0.1"
  - name: OTEL_SERVICE_NAME
    value: << inputs.name >>
  - name: TRACING_ENABLED
    value: "true"
```

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OTEL_COLLECTOR_ENDPOINT` | `otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318` | OTel Collector OTLP HTTP endpoint |
| `OTEL_SAMPLE_RATE` | `0.1` (10%) | Trace sampling rate (0.0–1.0) — wrapped in `ParentBased` |
| `TRACING_ENABLED` | `true` | Per-service traces kill switch |
| `ENV` | `production` | Environment label — **does not** auto-adjust sampling |

Full env table: [Application observability § Environment variables](./observability.md#environment-variables).

### Sampling {#sampling}

Configured inside `obsx.SetupObservability` as `ParentBased(TraceIDRatioBased(rate))`:

- **Production (cluster):** ~10% head sampling at Kong and services — statistically valid, ~90% storage savings.
- **Local-stack:** `OTEL_SAMPLE_RATE=1.0` for complete demo traces.
- **No ENV auto-mapping** — set `OTEL_SAMPLE_RATE` explicitly per environment.

| Environment | Recommended rate | Use case |
|-------------|------------------|----------|
| Production | 10% | Cost-effective, statistically valid |
| Staging | 50% | More coverage for testing |
| Development / local-stack | 100% | Full debugging visibility |

When a service receives a sampled remote parent, it **always honours** the parent's decision (`AlwaysOn` / `AlwaysOff`). Platform sampling narrative: [OpenTelemetry (platform) § Sampling](../observability/opentelemetry/README.md#sampling).

### Request filtering (automatic)

These endpoints are **never traced**:

| Path | Reason |
|------|--------|
| `/health`, `/healthz`, `/readyz`, `/livez` | High frequency, low value |
| `/metrics` | Legacy scrape path (retired for apps) |
| `/favicon.ico` | Browser noise |

gRPC health and reflection RPCs are filtered by `pkg/grpcx`.

### Service identity

`service.name` comes from **`OTEL_SERVICE_NAME`**, injected by every app ResourceSet — authoritative. Namespace and instance id ride via `OTEL_RESOURCE_ATTRIBUTES` (Downward API).

---

## Usage patterns

### When tracing helps

| Scenario | How tracing helps |
|----------|-------------------|
| Debugging slow requests | See which service/operation is slow |
| Investigating errors | Full error flow across services |
| SLO budget burn | Find root cause of latency/error spikes |
| Dependency mapping | Understand call patterns |
| Performance optimization | Identify bottlenecks (DB, external APIs) |

### Automatic capture

Every traced HTTP request includes service name, namespace, pod, HTTP method/path/status, duration, parent span ID, User-Agent, Remote IP, and W3C propagation.

### Helper functions

```go
// Record errors for debugging
middleware.RecordError(ctx, err)

// Add business context (bounded labels — no PII)
middleware.AddSpanAttributes(ctx,
    attribute.String("user.id", userID),
    attribute.String("order.id", orderID),
)

// Mark important events
middleware.AddSpanEvent(ctx, "payment.approved")

// Create child spans for complex operations
ctx, span := middleware.StartSpan(ctx, "validate-inventory")
defer span.End()
```

**When to use:**

- ✅ Recording errors (always)
- ✅ Adding user/order IDs for filtering (bounded IDs, not PII)
- ✅ Marking state transitions
- ❌ Don't trace in tight loops
- ❌ Don't add sensitive data (passwords, credit cards, tokens)

Use `layer=web` / `layer=logic` on spans per [three-layer architecture](./observability.md#three-layer-architecture).

---

## Best practices

### Production recommendations

| Practice | Why | Implementation |
|----------|-----|----------------|
| ~10% sampling | Balance cost vs visibility | `OTEL_SAMPLE_RATE=0.1` |
| Auto-filter health checks | Reduce noise 30–40% | Automatic (middleware) |
| Always record errors | Critical for debugging | `RecordError(ctx, err)` |
| Graceful shutdown | Zero lost spans on rollout | `obs.Shutdown()` on exit |
| Correlate with logs | Jump trace ↔ logs via `trace_id` | Tracing before logging middleware |

### Do's

1. Record all errors for debugging context
2. Add business IDs (user_id, order_id) for filtering — not unbounded promo codes
3. Use child spans for distinct operations (DB queries, external API calls)
4. Monitor trace volume in Grafana when changing sampling

### Don'ts

1. Don't trace in loops (span explosion)
2. Don't add sensitive data (passwords, tokens, PII)
3. Don't sample 100% in production without cause
4. Don't skip error recording

### Correlation with logs

Structured logs carry `trace_id` when a span is active (logging middleware runs after tracing):

```json
{
  "level": "error",
  "message": "Payment failed",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "error": "timeout"
}
```

Grafana Explore → Tempo → search by Trace ID. Details: [Application logging](./logs.md).

---

## References

- [Application observability](./observability.md)
- [Application logging](./logs.md)
- [Tracing (platform)](../observability/tracing/README.md)
- [Tracing architecture (platform)](../observability/tracing/architecture.md)
- [RFC-0014](../proposals/rfc/RFC-0014/)

_Last updated: 2026-07-22 — canonical app tracing contract._
