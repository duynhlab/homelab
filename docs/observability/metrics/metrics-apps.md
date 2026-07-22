# Application Metrics (RED)

The **application layer** of the metrics pillar: the RED signals (Rate, Errors,
Duration) for the 10 currently cluster-deployed Go microservices and their gRPC east-west calls, plus Go
runtime health and the instrumentation that produces it. Since the RFC-0014 P3
cutover these metrics are **pushed over OTLP** (no `/metrics` scrape); names and
labels follow OpenTelemetry semantic conventions. For methodology theory, the
stack, and the other layers, start at the [metrics hub](README.md).

| | |
|---|---|
| **Source** | OTLP push — each service's OTel SDK (`pkg/obsx`) exports to `otel-collector`; **no app `/metrics` scrape** |
| **Core metric** | `http_server_request_duration_seconds` (histogram) — single source of RED |
| **East-west** | gRPC RED on the *same* OTLP stream via `pkg/obsx` / `pkg/grpcx` |
| **App labels** | `http_request_method`, `http_route`, `http_response_status_code` |
| **Provenance** | `app` / `namespace` from OTLP resource attributes + vmagent relabel |
| **Correlation** | `trace_id` field in VictoriaLogs + Tempo (exemplars lost — [D-14](../../proposals/rfc/RFC-0014/README.md)) |
| **Dashboard** | Microservices dashboard (see [§ Dashboard](#dashboard)) |
| **Runbooks** | [`../runbooks/microservices/README.md`](../runbooks/microservices/README.md) (one file per alert) |
| **Hub** | Workflows & tuning: [`../runbooks/microservices-alerts.md`](../runbooks/microservices-alerts.md) |

---

## Learning path

1. **RED on one histogram** — read [Application metrics](../../api/metrics.md) (authoring), then this doc for alerts/dashboards.
2. **East-west gRPC** — [Application metrics § gRPC](../../api/metrics.md) (authoring); alert map below for on-call.
3. **Runtime USE** — [Availability heartbeat](#availability--the-heartbeat-not-up) + [Memory leak & GC](#memory-leak--gc-diagnosis) (platform ops).
4. **App-side DB** — [Application metrics § Database client](../../api/metrics.md); server-side [PostgreSQL runbooks](../runbooks/postgresql/README.md).
5. **When an alert fires** — open the matching file in [`runbooks/microservices/`](../runbooks/microservices/README.md); use [workflows in the hub](../runbooks/microservices-alerts.md#4-investigation-workflows) for cross-signal triage.

## Signal → alert map

| Symptom / signal | Primary metrics | Layer-1 alert(s) | Runbook |
|------------------|-----------------|------------------|---------|
| Instance stopped reporting | `go_goroutine_count` heartbeat | `MicroserviceDown` | [MicroserviceDown](../runbooks/microservices/MicroserviceDown.md) |
| All pods silent | heartbeat per `(app,namespace)` | `MicroserviceAllInstancesDown` | [MicroserviceAllInstancesDown](../runbooks/microservices/MicroserviceAllInstancesDown.md) |
| Collector blind | `otelcol_exporter_send_failed_metric_points` | `OtelMetricsPipelineExportFailures` | [OtelMetricsPipelineExportFailures](../runbooks/microservices/OtelMetricsPipelineExportFailures.md) |
| HTTP 5xx spike | `http_server_request_duration_seconds_count` | `MicroserviceHighErrorRate` / `MicroserviceErrorRateCritical` | [HighErrorRate](../runbooks/microservices/MicroserviceHighErrorRate.md) |
| Zero 2xx | same + status filter | `MicroserviceNoSuccessfulRequests` | [NoSuccessfulRequests](../runbooks/microservices/MicroserviceNoSuccessfulRequests.md) |
| gRPC callee errors | `rpc_server_call_duration_seconds_count` | `GrpcServerHighErrorRate` | [GrpcServerHighErrorRate](../runbooks/microservices/GrpcServerHighErrorRate.md) |
| Slow HTTP | `http_server_request_duration_seconds_bucket` | P95/P99 / `MicroserviceLatencyCritical` | [HighLatencyP95](../runbooks/microservices/MicroserviceHighLatencyP95.md) |
| Slow gRPC | `rpc_server_call_duration_seconds_bucket` | `GrpcServerHighLatencyP95` | [GrpcServerHighLatencyP95](../runbooks/microservices/GrpcServerHighLatencyP95.md) |
| Routing / upstream | request rate → 0 | `MicroserviceNoTraffic` | [MicroserviceNoTraffic](../runbooks/microservices/MicroserviceNoTraffic.md) |
| User-perceived slowness | Apdex recording rule | `MicroserviceApdexCritical` | [MicroserviceApdexCritical](../runbooks/microservices/MicroserviceApdexCritical.md) |
| Goroutine climb | `go_goroutine_count` + `deriv()` | `MicroserviceGoroutineLeak` | [MicroserviceGoroutineLeak](../runbooks/microservices/MicroserviceGoroutineLeak.md) |
| Memory near limit | cAdvisor working-set / limits | `MicroserviceHighMemoryUsage` | [MicroserviceHighMemoryUsage](../runbooks/microservices/MicroserviceHighMemoryUsage.md) |
| Slow SQL (app view) | `db_client_operation_duration_seconds` | `DBClientQueryP95High` | [DBClientQueryP95High](../runbooks/microservices/DBClientQueryP95High.md) |
| DB errors (app view) | `db_client_operation_errors_total` | `DBClientErrorRate` | [DBClientErrorRate](../runbooks/microservices/DBClientErrorRate.md) |
| Pool pinned | `pgxpool_acquired_connections` | `PgxPoolNearExhaustion` | [PgxPoolNearExhaustion](../runbooks/microservices/PgxPoolNearExhaustion.md) |
| Pool waits | `pgxpool_empty_acquire_total` | `PgxPoolAcquireWaitHigh` | [PgxPoolAcquireWaitHigh](../runbooks/microservices/PgxPoolAcquireWaitHigh.md) |

Full catalog: [alert-catalog §1](../alerting/alert-catalog.md#1-microservices-red-metrics).

---

> **Service authors:** instrument names, cardinality rules, business metric
> authoring, and middleware wiring are canonical in
> [**Application metrics**](../../api/metrics.md). This doc keeps the **platform
> view** — alert map, dashboards, troubleshooting, and manifest paths.

Microservices are measured with the **RED method** on a single OTLP-exported
histogram (`http_server_request_duration_seconds`). East-west gRPC follows the
same model on `rpc_*` instruments. For the full authoring reference (HTTP RED,
labels, DB client metrics, gRPC, business metrics, instrumentation wiring, and
correlation workflow), see [**Application metrics**](../../api/metrics.md).

Per-service business instrument catalog (all 34 shipped metrics):
[metrics-catalog.md](metrics-catalog.md).

## Memory leak & GC diagnosis

The Go Runtime row of the dashboard supports systematic diagnosis:

| Memory | Goroutines | GC pressure | Diagnosis | Action |
|--------|------------|-------------|-----------|--------|
| ↑↑↑ | → | used ≈ goal | **Heap leak** | Caches without eviction, global maps, unclosed resources |
| →/↑ | ↑↑↑ | → | **Goroutine leak** | Forgotten `defer cancel()`, unclosed channels, blocking ops |
| ↑↓ | ↑↓ | used ≈ goal | **High load** (OK) | Traffic up, app coping — not a leak |
| → | → | headroom | **Healthy** | No action |

Workflow: watch `go_memory_used_bytes` and cAdvisor
`container_memory_working_set_bytes` — sustained climb ⇒ heap leak; watch
`go_goroutine_count` — steady climb ⇒ goroutine leak; confirm GC pressure by
comparing `go_memory_used_bytes` against `go_memory_gc_goal_bytes` (persistently
within a few percent means the collector is running back-to-back). The
`MicroserviceGCThrash` alert encodes exactly this used-vs-goal comparison, since
no GC-pause metric exists.

## Availability — the heartbeat, not `up`

Under OTLP push there is **no `up{job="microservices"}`** (that series was a
scrape artifact). Liveness is derived from the runtime heartbeat: `go_goroutine_count`
is exported every ~15 s regardless of traffic. A pod is "down" when its
heartbeat series existed in the last 15 m but no longer does:

```promql
count by (app, namespace, k8s_pod_name) (last_over_time(go_goroutine_count{app!=""}[15m]))
  unless
count by (app, namespace, k8s_pod_name) (go_goroutine_count{app!=""})
```

VictoriaMetrics keeps returning the last sample for ~5 m (staleness window), so
detection **lags a pod kill by about 5 minutes** — accepted in RFC-0014 D-4 and
verified by the P3 pod-kill test. The push pipeline itself is now an availability
dependency, so a collector export-failure alert
(`otelcol_exporter_send_failed_metric_points`) runs alongside to
disambiguate "service down" from "pipeline broken".

## Dashboard

Two dashboards consume this layer. The **Microservices dashboard** (RED + Golden
Signals) groups panels into: Overview & key metrics, Traffic & requests, Errors
& performance, Go runtime & HTTP I/O, and **gRPC East-West (RED)** (server/client
RPS, error rate, P95 by `rpc_method`). The **Business KPIs dashboard**
(`business-otel-local`, RFC-0017) adds one collapsible **row per domain** —
Payments, Orders/Saga, Auth, Product, Cart, Shipping, User, Review,
Notification, Checkout — built from the hand-declared Business instruments (decline
rate, saga outcomes, AOV, cache hit-ratio, promo redemptions, …). The
local-stack ships both under `local-stack/observability/grafana/dashboards/`;
the cluster twins render from the `mop`/helm charts.

Which metric powers which panels:

| Metric | Used by |
|--------|---------|
| `http_server_request_duration_seconds_count` | RPS, success/error rate, status distribution, per-endpoint, 4xx/5xx |
| `http_server_request_duration_seconds_bucket` | P50/P95/P99, Apdex |
| `http_server_request_body_size_bytes_sum` / `http_server_response_body_size_bytes_sum` | Network RX / TX |
| `rpc_{server,client}_call_duration_seconds_*` | gRPC East-West row |
| `go_goroutine_count` / `go_memory_used_bytes` / `container_memory_working_set_bytes` | Runtime, memory, liveness heartbeat |
| `kube_pod_container_status_restarts_total` | Restarts (kube-state-metrics) |

Variables: `$DS_PROMETHEUS`, `$namespace`, `$app` (cascades from `$namespace`,
keyed off `go_goroutine_count`), `$rate`. See
[Grafana Dashboard Guide](../grafana/dashboard-reference.md) and
[Variables & Regex Guide](../grafana/variables.md). For `$rate` vs `$__range` and
counter-reset handling, see the [PromQL Guide](promql-guide.md).

## Troubleshooting — cardinality

Symptoms: slow PromQL, high-cardinality warnings, high VictoriaMetrics memory.

```promql
count by (__name__) ({app!=""})                           # series per metric (target < 5000)
count(count by (http_route) ({app!=""}))                  # unique routes (target < 30/service)
topk(10, count by (__name__) ({app!=""}))                 # worst offenders
```

Prevention: route normalization (`http_route` from the matched pattern) keeps
routes bounded; the vmagent resource-attr allowlist blocks
`service.instance.id` / `process.pid` re-minting; never put raw IDs, emails, or
IPs in labels.

## Manifest index

The app metrics now arrive by **OTLP push**, so this layer owns the ingest and
consumer config, not a scrape config. The alert and recording rules that consume
these metrics are catalogued (with counts and production impact) in the
[Alert Catalog](../alerting/alert-catalog.md).

| Manifest (under `kubernetes/infra/configs/observability/`) | Purpose |
|------|---------|
| `victoriametrics/vmagent.yaml` | OTLP ingest args (`usePrometheusNaming`, resource-attr allowlist) + `service_name→app` / `k8s_namespace_name→namespace` relabel |
| `prometheusrules/microservices/recording-rules.yaml` | RED/latency/Apdex/bandwidth + gRPC pre-aggregation under the `app:` / `app_route:` prefixes |
| `prometheusrules/microservices/alerts.yaml` | RED/Golden + runtime + D-4 heartbeat-absence + collector-pipeline alerts |

The `otel-collector` deployment (metrics pipeline) and the SDK exporter config
live with the [OpenTelemetry](../opentelemetry/README.md) setup. There is no app
`ServiceMonitor` — scrape configs remain only for infra exporters.

- **Alerts + recording rules** — see
  [Alert Catalog → Microservices](../alerting/alert-catalog.md#1-microservices-red-metrics)
  and [Alerting Strategy](../alerting/README.md#layer-1-threshold-alerts-immediate-detection).
- **SLOs** — rendered per service by the `mop` chart (not a repo path) and
  expanded by Sloth into burn-rate alerts. See [SLO docs](../slo/README.md).

Runbooks: [`runbooks/microservices/README.md`](../runbooks/microservices/README.md) (per alert) · hub [`microservices-alerts.md`](../runbooks/microservices-alerts.md).

## References

- [Metrics hub](README.md) · [Infrastructure metrics (USE)](metrics-infra.md) · [Database metrics](postgresql/README.md)
- [OpenTelemetry setup](../opentelemetry/README.md) · [RFC-0014: full OpenTelemetry adoption](../../proposals/rfc/RFC-0014/README.md)
- [API → gRPC runtime model](../../api/api.md#grpc-runtime-model) · [API reference](../../api/api.md)
- [PromQL Guide](promql-guide.md) · [SLO Documentation](../slo/README.md)
- [Grafana Dashboard Guide](../grafana/dashboard-reference.md) · [Variables & Regex Guide](../grafana/variables.md)

---

_Last updated: 2026-07-18 — Phase 2 runbook split: learning path + signal→alert map; per-alert files under `runbooks/microservices/`._
</content>
</invoke>
