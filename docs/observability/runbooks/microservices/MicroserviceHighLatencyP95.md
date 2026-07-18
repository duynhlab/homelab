# MicroserviceHighLatencyP95

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
P95 latency exceeds 1 second for 10 minutes.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Diagnosis
### Possible causes
- Slow database queries (missing index, table scan)
- Downstream service latency (cascading slowness)
- Resource contention (CPU throttling, GC pressure)
- Connection pool exhaustion (waiting for connections)

### Investigation
```promql
# P95 latency by service
app:http_server_request_duration_seconds:p95_5m{app="$APP"}

# P95 by endpoint (find slow endpoints)
app_route:http_server_request_duration_seconds:p95_5m{app="$APP"}

# Check saturation: the in-flight signal is no longer emitted -- otelgin exposes no
# http_server_active_requests, so the requests-in-flight alerts retired (RFC-0014 — otelgin gap)

# Check GC thrash (GC churn causing latency?). There is no GC-pause metric under OTLP;
# instead watch the heap riding its GC goal (>0.95 = thrashing):
go_memory_used_bytes{app="$APP"} / go_memory_gc_goal_bytes{app="$APP"}
```

**Grafana panels to check**:
- Row 1: P95 Response Time (stat panel)
- Row 3: Response time 95th percentile (per endpoint)
- Row 5: Requests In Flight

## Mitigation
1. Identify slow endpoint from per-endpoint P95
2. Find the slow request in VictoriaLogs (filter on high latency), then open its `trace_id` in Tempo (traces<->logs correlation). Exemplars are not available -- VictoriaMetrics does not support them (RFC-0014 D-14)
3. In the trace waterfall, find the slowest span (DB query? external API?)
4. If DB: add index, optimize query, check `PgxPoolNearExhaustion` (app pool) and `CNPGClusterHighConnectionsWarning` (DB side)
5. If GC: watch the heap-vs-GC-goal ratio above (`go_memory_used_bytes / go_memory_gc_goal_bytes`), review Pyroscope CPU profile
6. If saturation: scale up replicas
