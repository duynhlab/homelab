# MicroserviceHighLatencyP99

| | |
|---|---|
| **Severity** | warning |
| **Category** | latency |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml` |
| **Metrics** | `http_server_request_duration_seconds_bucket` |
| **Status** | active |
| **Dashboard** | Microservices → the service RED board |

## Meaning

P99 latency exceeds 2 seconds for 10 minutes. P99 is tail latency — the worst
1% of requests. High P99 with a normal P95 means occasional outlier requests,
not across-the-board slowness; when P95 rises too, this is the same incident
as [MicroserviceHighLatencyP95](MicroserviceHighLatencyP95.md) seen from the
tail. This alert is diagnostic — the page for user-facing slowness comes from
the latency SLO burn-rate, not from here.

## Impact

One request in a hundred takes multiple seconds. That sounds small, but a
shopper journey chains many requests, so the odds of hitting the tail at least
once per session are much higher than 1%. Tail latency also feeds retry storms:
clients time out, retry, and add load exactly when the service is slowest.
Impact is conditional — if P95 and the SLO burn-rate are quiet, this is a
tuning signal, not an outage.

## Diagnosis

Causes beyond the [P95 list](MicroserviceHighLatencyP95.md) (which covers slow
queries, downstream latency, resource contention, pool exhaustion) — the
tail-specific ones: retry storms from downstream clients, lock contention in
the database, and cold starts after idle (first request warming caches).

### PromQL

```promql
# Alert expr
histogram_quantile(0.99,
  sum by (app, namespace, le) (rate(http_server_request_duration_seconds_bucket{app!=""}[5m]))
) > 2

# Tail vs body — outliers (P99 alone) or across-the-board (P95 up too)?
app:http_server_request_duration_seconds:p99_5m{app="$APP"}
app:http_server_request_duration_seconds:p95_5m{app="$APP"}

# Which route owns the tail?
app_route:http_server_request_duration_seconds:p95_5m{app="$APP"}

# Pool waits — a classic tail-only cause
sum by (app) (rate(pgxpool_empty_acquire_total{app="$APP"}[5m]))

# GC thrash — heap riding its GC goal (>0.95 = thrashing)
go_memory_used_bytes{app="$APP"} / go_memory_gc_goal_bytes{app="$APP"}
```

### Grafana

- **Microservices → the service RED board** — is the tail periodic (cron,
  cache expiry), pinned to one pod, or spread evenly?

### kubectl / logs

```bash
APP=<app label>; NS=<namespace label>
kubectl -n "$NS" get pods -l app="$APP"    # one restarted pod = cold-start tail
kubectl top pod -n "$NS" -l app="$APP"     # CPU near limit = throttling tail
```

### VictoriaLogs / traces

Find the slow requests in VictoriaLogs (`{app="$APP"}`, filter on high
latency) and open their `trace_id` in VictoriaTraces — exemplars are not available
(VictoriaMetrics does not support them, RFC-0014 D-14), so the log→trace pivot
is the path. In the waterfall, tail requests usually show one long span: a
lock wait, a pool acquire, or a retried downstream call.

## Mitigation

1. Localize first: one route, one pod, or fleet-wide (per-route P95 and
   `kubectl top` above). A single-pod tail is usually a restart/cold-start —
   often self-healing.
2. If pool waits show up, follow
   [PgxPoolAcquireWaitHigh](PgxPoolAcquireWaitHigh.md) — the tail is queueing.
3. If the trace shows retried downstream calls, fix the downstream latency
   first; tightening this service's timeouts only reshapes the tail.
4. If GC thrash, review the Pyroscope CPU profile; scale replicas only when
   the trace shows genuine saturation, not a lock or a pool.

## Escalation

Ticket by default — this is a diagnostic alert; the page comes from the
latency SLO. Escalate when `MicroserviceLatencyCritical` or
[MicroserviceHighLatencyP95](MicroserviceHighLatencyP95.md) co-fires on the
same `app` (the body of the distribution is moving, not just the tail), or
when the SLO burn-rate pages. **Do not** scale up replicas as a reflex: if the
tail comes from DB lock contention or pool waits, more replicas add more
contenders and make the tail worse.

## Related

- [MicroserviceHighLatencyP95](MicroserviceHighLatencyP95.md) — same metric,
  body of the distribution; shares the core cause list.
- [MicroserviceLatencyCritical](MicroserviceLatencyCritical.md) — P95 >2s.
- [PgxPoolAcquireWaitHigh](PgxPoolAcquireWaitHigh.md) — queueing only the tail sees.

---
_Last updated: 2026-08-19 — rewritten to the canonical template (was a stub)_
