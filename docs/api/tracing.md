# Application Tracing

Distributed tracing contract for every Go service and worker in the platform service catalog — sampling, span helpers, propagation, and best practices.

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **SDK** | `obsx.SetupObservability()` — one call in `main()` | — |
| **Propagation** | W3C Trace Context (`traceparent`), native at the edge and in every service | — |
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

### Sampling

Configured inside `obsx.SetupObservability` as `ParentBased(TraceIDRatioBased(rate))`:

- **Production (cluster):** ~10% head sampling at the edge and in services — statistically valid, ~90% storage savings.
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

| Path prefix | Reason |
|-------------|--------|
| `/health`, `/healthz`, `/ready`, `/readyz`, `/livez` | High frequency, low value |
| `/metrics` | Legacy scrape path (retired for apps) |
| `/favicon.ico` | Browser noise |

The skip list is a **prefix** match in each service's `TracingMiddleware`
(`shouldTrace`), applied before `otelgin` runs — so these paths emit neither
spans nor `http.server.*` metrics. gRPC health and reflection RPCs are filtered
by `pkg/grpcx`.

### Service identity

`service.name` comes from **`OTEL_SERVICE_NAME`**, injected by every app ResourceSet — authoritative. Namespace and instance id ride via `OTEL_RESOURCE_ATTRIBUTES` (Downward API).

### Propagation

Services accept and propagate W3C Trace Context (`traceparent`). The edge speaks
W3C natively: Envoy starts a span for every request it accepts and sends
`traceparent` upstream, so a browser request that carries no trace header still
arrives at the service already joined to the edge trace. The edge is therefore
the root sampling authority — its `samplingRate` decides, and because Envoy's
sampler is ParentBased, an inbound sampled decision is always honoured.
Configured in the `EnvoyProxy` resource (`telemetry.tracing`) in
`kubernetes/infra/configs/envoy-gateway/envoyproxy.yaml` for the cluster and
`local-stack/gateway/eg/envoyproxy.yaml` locally. gRPC metadata carries the same
context via `pkg/grpcx`.

### Baggage

Baggage is request-scoped key-value context that rides the W3C **`baggage`**
header next to `traceparent`. `pkg/obsx` installs the composite propagator
(`TraceContext` + `Baggage`), so any baggage set on the context **propagates
automatically** on every instrumented HTTP/gRPC call — no custom headers, no
parameter drilling through intermediate services.

Rules when a use case is approved:

- Baggage is **immutable** — each set returns a new context; use *that*
  context for downstream calls or the value never leaves the process.
- Backends **do not store baggage**. To analyze it later, copy the value onto
  a span attribute or log field at the service that consumes it.
- Unlike span attributes (retrospective), baggage is readable **at runtime**
  by downstream services — the legitimate use case is steering behavior
  (feature flags, A/B variant) without a shared metadata store.
- **Security:** baggage is attached to outbound calls indiscriminately,
  including third-party HTTP calls — never put PII, tokens, or secrets in it,
  and strip keys before calling external providers.

The platform default remains **no application baggage**: new baggage keys
require review because they propagate across every downstream hop and add
per-request header cost.

---

## Automatic instrumentation

Automatic spans — do not duplicate these with manual spans:

- HTTP server span from `otelgin` (via `TracingMiddleware`);
- gRPC server/client spans from `otelgrpc` (via `pkg/grpcx`);
- DB spans from shared DB instrumentation (`otelpgx`);
- supported external-client spans.

Automatic capture includes service identity, route template or RPC method,
HTTP/gRPC status, duration, and W3C propagation fields per semconv. Note the
split: **spans** carry only what `otelgin`/`otelgrpc` emit per semconv, while
the HTTP **access log** additionally records `client_ip` and `user_agent`
today (see [logs.md § Access-log policy](./logs.md#access-log-policy)); adding
IP/User-Agent to spans is not part of the contract and requires
privacy/retention review.

---

## Manual instrumentation

HTTP server, gRPC client/server, and supported database spans are automatic.
Do not add a second generic span around an already-instrumented request or RPC.

The granularity ladder, in order of preference:

1. **Attributes on the existing span** — business context the auto span is
   missing (`middleware.AddSpanAttributes`).
2. **A span event** — a milestone *inside* one operation ("provider
   contacted", "response received") that needs a timestamp but not its own
   duration.
3. **A child span** — only when the operation deserves its own duration and
   error status: a multi-step domain use case, provider interaction,
   compensation, reconciliation, or expensive transformation.

A span per function call is the canonical anti-pattern — expensive to
produce, and it buries the request story under noise.

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

The helpers live in each service's own `middleware` package
(`<svc>-service/middleware/tracing.go` — copied per service, not in `pkg`);
signatures verified 2026-07-29:

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
Do not emit events in a loop — spans are not built for hundreds of events;
per-item detail belongs in correlated logs (or span links for cross-trace
fan-out).

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

_Last updated: 2026-07-29 — canonical app tracing contract; as-built claims verified against `duynhlab/pkg`, the service repos, and the edge config._
