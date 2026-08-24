# Distributed Tracing Guide

## Quick Summary

**What is Distributed Tracing?**
Track requests as they flow through multiple microservices to understand performance bottlenecks, debug errors, and visualize service dependencies.

**Key Capabilities:**
- ✅ Track request journeys across all 10 microservices
- ✅ Identify slow services and bottlenecks
- ✅ Debug cross-service errors with full context
- ✅ Correlate traces with logs (via trace_id)
- ✅ 10% sampling (configurable) for cost-effectiveness

**Technologies:**
- **OpenTelemetry**: Industry-standard tracing instrumentation
- **VictoriaTraces**: the fast trace path (`v0.11.0`, VM-operator-managed, VictoriaLogs engine) — PVC-backed, **7-day** retention, queried through the Jaeger API and, experimentally, TraceQL; see [victoriatraces.md](victoriatraces.md)
- **ClickHouse**: `otel_traces`, **90-day** SQL tier with a `trace_id` JOIN against `otel_logs` ([ADR-023](../../proposals/adr/ADR-023-clickhouse-observability-olap/)); see [clickhouse](../clickhouse/README.md)
- **W3C Trace Context**: Standard for trace propagation between services
- **Retired**: Tempo and Jaeger were removed under [RFC-0027](../../proposals/rfc/RFC-0027/README.md) ([ADR-058](../../proposals/adr/ADR-058-retire-jaeger/), [ADR-059](../../proposals/adr/ADR-059-retire-tempo/)). Their manifests stay in the tree as `*.yaml.bak`, and what running them taught is archived in [tempo.md](tempo.md) and [jaeger.md](jaeger.md) — frozen, kept as learning material
- **Span metrics**: RED series are derived by the collector's `span_metrics` **connector**, not by a trace backend ([ADR-057](../../proposals/adr/ADR-057-span-metrics-in-collector/)) — so they no longer depend on which store survives

---

## Table of Contents

1. [Why Distributed Tracing?](#why-distributed-tracing) - Real-world use cases
2. [How It Works](#how-it-works) - System architecture
3. [Configuration, usage, and best practices](#configuration-usage-and-best-practices) - App contract → [api/tracing.md](../../api/tracing.md)
4. [Troubleshooting](#troubleshooting) - Common issues

---

## Why Distributed Tracing?

### Real-World Use Cases

#### 1. **Debugging Cross-Service Issues** 🔍
**Problem**: User reports "checkout is slow" but the request crosses several services and workers.

**Without tracing**: Check logs from every service and worker manually, then guess which hop is slow.

**With Tracing**: 
- See the entire request flow: `Edge → Order → Shipping / Notification`
- Identify bottleneck: **Shipping service took 2000ms** (everything else < 100ms)
- Jump to Shipping logs using `trace_id` to see exact error

#### 2. **Performance Optimization** ⚡
**Scenario**: Dashboard shows `/api/v1/orders` P95 latency = 800ms (SLO target: 500ms).

**With Tracing**:
- Find slowest spans: Database query (600ms), External API call (150ms)
- Add database index → latency drops to 300ms
- Verify improvement with trace comparison

#### 3. **Error Budget Investigation** 🚨
**Alert**: `order` service SLO burn rate critical (1.5% error rate, budget: 1%).

**With Tracing**:
- Filter traces with `http.status_code=500`
- See error pattern: `Order → Shipping → TIMEOUT`
- Root cause: Shipping service timeout (30s → need circuit breaker)

#### 4. **Service Dependency Mapping** 🗺️
**Question**: "If I update `shipping` service, which services will be affected?"

**With Tracing (Service Graph)**:
- Visualize dependencies: `Order → Shipping`, `Order → Notification`, `Product → Review` (gRPC east-west)
- Plan deployment order: update `Shipping` before `Order`
- Monitor impact with trace sampling

---

## How It Works

### Architecture

```mermaid
flowchart LR
    A[User Request] -->|1. HTTP Request| K[Envoy Gateway edge<br/>root span + traceparent]
    K -->|2. W3C traceparent header| C[Order Service]
    C -->|3. traceparent via gRPC metadata| D[Shipping Service]

    K -->|Spans OTLP/gRPC :4317| O[OTel Collector]
    C -->|Spans OTLP| O
    D -->|Spans OTLP| O

    O --> V["VictoriaTraces · 7d"]
    O --> CH[("ClickHouse otel_traces · 90d")]

    V -->|"Jaeger query API"| F[Grafana]
    CH -->|"SQL"| F

    classDef edge fill:#2563eb,color:#fff,stroke:#1e3a8a;
    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef trace fill:#c5f6fa,color:#111,stroke:#0c8599;
    classDef collector fill:#a5d8ff,color:#111,stroke:#1971c2;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    class A,K edge;
    class C,D service;
    class O collector;
    class V trace;
    class CH data;
    class F platform;
```

### Trace Flow

1. **Request arrives** at the **edge** (Envoy Gateway), which creates the **root span** with `trace_id` and propagates the W3C `traceparent` — native tracing (`EnvoyProxy.spec.telemetry.tracing`), no plugin required
2. **W3C Trace Context** header (`traceparent`) propagated to the services and downstream
3. Each service creates **child spans** for its operations (the edge propagates a W3C `traceparent` natively on every proxied request — see [edge→service linkage](architecture.md#edge--service-linkage))
4. **10% sampling** — the edge (root) decides by ratio (`samplingRate: 10` in the cluster CR, **planned**; `100` in local-stack); each service wraps its ratio in `ParentBased` (`ParentBased(TraceIDRatioBased(rate))`), so downstream hops honour the root's `sampled` flag and traces stay whole — a service's own ratio only applies when it is itself the root (see the [sampling note](architecture.md#edge--service-linkage))
5. Spans exported via OTLP HTTP (batch export every 5s) to the **OTel Collector**, which fans out to **two** sinks: **VictoriaTraces** (7d) and **ClickHouse** `otel_traces` (90d)
6. **Grafana** queries VictoriaTraces through the **Jaeger datasource type**, and ClickHouse with SQL

> **Two sinks, two windows.** Read the collector's `service.pipelines` for the
> authoritative list — it is the only place the real answer lives.
>
> | Sink | Store | Retention | Role |
> |---|---|---|---|
> | **VictoriaTraces** `v0.11.0` | PVC 10Gi | 7d | The fast path: open one trace mid-investigation. Queried via the Jaeger API (`/select/jaeger`), and via TraceQL at `/select/tempo` — the latter is upstream-**experimental**, see [victoriatraces.md](victoriatraces.md) |
> | **ClickHouse** | `otel_traces` | **90d** | Long-retention SQL and a `trace_id` JOIN against `otel_logs` ([ADR-023](../../proposals/adr/ADR-023-clickhouse-observability-olap/), [clickhouse](../clickhouse/README.md)) |
>
> It used to be five. Tempo ran twice and Jaeger kept traces in a memory ring, and three of
> the five answered the same question over the same window — so [RFC-0027](../../proposals/rfc/RFC-0027/README.md)
> retired both. The service map that Tempo's generator used to feed now comes from
> VictoriaTraces' own dependency endpoint; what the duplication taught is in
> [tempo.md](tempo.md). See [architecture.md](architecture.md) and the
> [backend comparison](backends-comparison.md).

### Automatic Features

| Feature | What It Does | Benefit |
|---------|--------------|---------|
| **10% Sampling** | Only trace 10% of requests | Cost-effective, production-ready |
| **Request Filtering** | Skip `/health`, `/metrics` | Reduces noise by 30-40% |
| **Service Identity** | `OTEL_SERVICE_NAME` env injected by the app ResourceSets | Stable `service.name`, no per-service config |
| **Graceful Shutdown** | Flush pending spans on SIGTERM | Zero data loss during rollouts |
| **Error Recording** | Automatically mark error spans | Easy error filtering in Grafana |

### Accessing Traces

**Grafana Explore:**
```bash
kubectl port-forward -n monitoring svc/grafana-service 3000:3000
# Open http://localhost:3000 → Explore → VictoriaTraces datasource (type: jaeger)
```

**Search Options:**
- By service: `{resource.service.name="auth"}`
- By trace ID: `trace_id` from logs
- By status: `{status=error}`
- By duration: `{duration > 500ms}`

---

## Configuration, usage, and best practices

> **Service authors:** sampling env vars, span helpers, propagation rules, and
> production do/don't guidance are canonical in
> [**Application tracing**](../../api/tracing.md). This guide keeps the
> **platform view** — backends, Grafana queries, and on-call troubleshooting.

See [**Application tracing**](../../api/tracing.md) for:
- ResourceSet / env configuration (`OTEL_SAMPLE_RATE`, `TRACING_ENABLED`, …)
- Usage patterns (when to trace, helper functions)
- Best practices (sampling, error recording, log correlation)

## Troubleshooting

### Problem: No traces appearing in Grafana

**Possible Causes:**
1. **Sampling too low** → Temporarily increase to 100% for debugging:
   ```bash
   kubectl set env deployment/auth OTEL_SAMPLE_RATE=1.0 -n auth
   ```

2. **Trace store not running**:
   ```bash
   kubectl get pods -n monitoring -l app.kubernetes.io/name=vtsingle
   kubectl logs -n monitoring -l app.kubernetes.io/name=vtsingle
   ```

3. **Service not sending traces** — check the collector received them at all, since it is
   the single fan-out point:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=opentelemetry-collector | grep -i error
   kubectl logs -n checkout -l app=checkout | grep -i trace
   ```

### Problem: Trace volume too low

**Expected:** `trace_count ≈ request_count * sample_rate`

**Check:**
1. **Verify sampling rate**:
   ```bash
   kubectl get deployment auth -n auth -o yaml | grep OTEL_SAMPLE_RATE
   ```

2. **Check request filtering** (health checks automatically skipped)

3. **Monitor span ingestion** — read it at the collector rather than at a store, so the
   query survives a backend change:
   ```promql
   rate(otelcol_receiver_accepted_spans[5m])
   rate(otelcol_exporter_sent_spans[5m])
   ```

### Problem: High memory usage

**Solutions:**
1. **Reduce sampling**: `OTEL_SAMPLE_RATE=0.05` (5%)
2. **Verify no tracing in loops**: `grep -r "StartSpan.*for.*range" ~/Working/duynhlab/*-service`
3. **Check batch timeout** (default 5s is optimal)

### Problem: Missing traces during pod restarts

**Solution:** Graceful shutdown is already configured (automatic span flushing). If still missing:

1. **Check shutdown logs**:
   ```bash
   kubectl logs -n auth <pod> | grep -i shutdown
   ```

2. **Increase shutdown timeout** (if needed):
   ```go
   shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
   ```

### Debugging Commands

```bash
# View traces in Grafana
kubectl port-forward -n monitoring svc/grafana-service 3000:3000

# Check the trace store directly (Jaeger-compatible API)
kubectl port-forward -n monitoring svc/vtsingle-victoria-traces 10428:10428
curl -s http://localhost:10428/select/jaeger/api/services

# View service logs with trace IDs
kubectl logs -n checkout -l app=checkout | jq '.trace_id'

# Check sampling config
kubectl describe deployment auth -n auth | grep -A 5 "Environment"
```

---

## Reference

### Key Concepts

| Term | Definition |
|------|------------|
| **Trace** | Complete journey of a request across services |
| **Span** | Single operation within a trace (e.g., HTTP request, DB query) |
| **Trace ID** | Unique identifier for entire trace (128-bit) |
| **Span ID** | Unique identifier for single span (64-bit) |
| **W3C Trace Context** | Standard header format: `traceparent: 00-<trace-id>-<span-id>-<flags>` |
| **Sampling** | Percentage of requests to trace (10% = 1 in 10 requests) |

### Semantic Conventions (OpenTelemetry)

**HTTP Attributes:**
```go
attribute.String("http.method", "POST")
attribute.String("http.route", "/api/v1/orders")
attribute.Int("http.status_code", 200)
```

**Database Attributes:**
```go
attribute.String("db.system", "postgresql")
attribute.String("db.operation", "SELECT")
attribute.String("db.table", "users")
```

### Performance Characteristics

| Metric | Value | Notes |
|--------|-------|-------|
| Sampling overhead | < 1% CPU | At 10% sampling |
| Memory overhead | < 50MB | Per service |
| Export latency | < 100ms P99 | To VictoriaTraces |
| Trace volume reduction | 90% | vs 100% sampling |
| Request filtering reduction | 30-40% | Health/metrics skipped |

### External Resources

- [OpenTelemetry Go SDK](https://opentelemetry.io/docs/instrumentation/go/)
- [W3C Trace Context Spec](https://www.w3.org/TR/trace-context/)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)

---



---
_Last updated: 2026-08-24 — the fan-out is **two** sinks. RFC-0027 retired Tempo (both
installs) and Jaeger; the "Tempo runs twice" section moved to the archived
[tempo.md](tempo.md), and the troubleshooting commands now read span flow at the collector
(`otelcol_receiver_accepted_spans`) instead of at a store, so they survive the next backend
change. Two commands also still targeted the `auth` namespace, retired with RFC-0024._
