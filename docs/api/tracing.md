# Application Tracing

Distributed tracing contract for every Go service and worker in the platform service catalog — sampling, span helpers, propagation, and best practices.

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **SDK** | `obsx.SetupObservability()` — one call in `main()` | — |
| **Propagation** | W3C Trace Context (`traceparent`); edge behavior from Kong config | — |
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

### Propagation

Services accept and propagate W3C Trace Context. Edge behavior is defined by
the deployed Kong tracing configuration. gRPC metadata carries the same context
via `pkg/grpcx`.

### Baggage

The platform does not use application baggage by default. New baggage keys
require review because they propagate across every downstream hop and can leak
data or add cost.

---

## Automatic instrumentation

Automatic spans — do not duplicate these with manual spans:

- HTTP server span from `otelgin` (via `TracingMiddleware`);
- gRPC server/client spans from `otelgrpc` (via `pkg/grpcx`);
- DB spans from shared DB instrumentation (`otelpgx`);
- supported external-client spans.

Automatic capture includes service identity, route template or RPC method,
HTTP/gRPC status, duration, and W3C propagation fields per semconv. IP and full
User-Agent are **not** guaranteed authoring-contract fields; enabling them
requires privacy/retention review.

---

## Manual instrumentation

HTTP server, gRPC client/server, and supported database spans are automatic.
Do not add a second generic span around an already-instrumented request or RPC.

Create a manual span only for a meaningful operation that is not otherwise
visible, such as a multi-step domain use case, provider interaction,
compensation, reconciliation, or expensive transformation.

### Span naming

| Prefer | Avoid |
|--------|-------|
| `checkout.confirm` | `confirm-checkout-123` |
| `inventory.reserve` | `reserve-SKU-991` |
| `payment.capture` | `capture-payment-44` |
| `order.compensate` | `rollback-order-42` |

Span names are stable operation classes. Business identifiers are
high-cardinality attributes and are added only when operationally justified.

### Helper functions

```go
// Record unexpected failures
middleware.RecordError(ctx, err)

// Add business context (high-cardinality IDs — use sparingly)
middleware.AddSpanAttributes(ctx,
    attribute.String("order.id", orderID),
)

// Mark important events
middleware.AddSpanEvent(ctx, "payment.authorized")

// Create child spans for meaningful operations
ctx, span := middleware.StartSpan(ctx, "inventory.reserve")
defer span.End()

span.SetAttributes(
    attribute.String("inventory.outcome", outcome),
)
```

**When to use:**

- ✅ Multi-step domain operations not visible through auto-instrumentation
- ✅ Provider interactions, compensation, or reconciliation boundaries
- ✅ Recording unexpected failures with `RecordError`
- ✅ High-cardinality business identifiers when operationally justified — see [cross-signal data policy](./observability.md#cross-signal-data-and-privacy-policy)
- ❌ Don't trace in tight loops
- ❌ Don't add a second generic HTTP/RPC request span
- ❌ Don't add sensitive data (passwords, credit cards, tokens)

Layer responsibilities: [Application observability § Observability responsibilities by layer](./observability.md#observability-responsibilities-by-layer).

### Errors

- Record unexpected failures on the span where they become meaningful.
- Set Error status for failed operations, not automatically for every expected
  business rejection.
- Add retry and compensation milestones as stable span events.
- Do not record secrets, raw payloads, or sensitive provider responses.

Expected business outcomes such as `NOT_FOUND`, `PRICE_CHANGED`,
`STOCK_UNAVAILABLE`, `PAYMENT_DECLINED`, or `INVALID_TRANSITION` may be normal
domain outcomes depending on the owning contract — not automatically
infrastructure errors. Error logging ownership:
[Application observability § Error ownership](./observability.md#error-ownership).

### Span events

Good events use stable names:

```text
payment.authorized
inventory.reserved
order.pivot_reached
compensation.started
compensation.completed
```

Events must use stable names. IDs and error details are attributes, subject to
the [cross-signal data policy](./observability.md#cross-signal-data-and-privacy-policy).

---

## Worker and Temporal behavior

- Activities may create spans using activity context.
- Temporal workflow code must remain deterministic — no arbitrary OTel export or
  network I/O from workflow code.
- Workflow logging uses Temporal-aware, replay-safe logging.
- Workflow/run/order IDs are high-cardinality attributes, not metric labels.
- Trace continuity through Temporal must come from the supported integration,
  not custom headers stored ad hoc in workflow input.

Full worker rules: [Application observability § Worker and Temporal instrumentation](./observability.md#worker-and-temporal-instrumentation).

---

## Best practices

### Production recommendations

| Practice | Why | Implementation |
|----------|-----|----------------|
| ~10% sampling | Balance cost vs visibility | `OTEL_SAMPLE_RATE=0.1` |
| Auto-filter health checks | Reduce noise 30–40% | Automatic (middleware) |
| Distinguish business vs infra errors | Avoid alert noise | See error semantics above |
| Graceful shutdown | Zero lost spans on rollout | Bounded `obs.Shutdown()` on exit |
| Correlate with logs | Jump trace ↔ logs via `trace_id` | Tracing before logging middleware |

### Do's

1. Use manual spans for meaningful domain operations only
2. Add business IDs as attributes when operationally justified — never in span names
3. Use child spans for distinct operations (provider calls, compensation)
4. Monitor trace volume in Grafana when changing sampling

### Don'ts

1. Don't trace in loops (span explosion)
2. Don't add sensitive data (passwords, tokens, PII)
3. Don't sample 100% in production without cause
4. Don't mark every expected business rejection as infrastructure failure

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

_Last updated: 2026-07-29 — canonical app tracing contract._
