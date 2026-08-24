# GrpcServerHighLatencyP95

| | |
|---|---|
| **Severity** | warning |
| **Category** | latency |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml` |
| **Metrics** | `rpc_server_call_duration_seconds_bucket` |
| **Status** | active |
| **Dashboard** | Microservices → the service RED board |
| **Applies to** | services exposing gRPC servers (east-west callees, e.g. inventory) |

## Meaning

P95 latency for **incoming gRPC calls** on a service exceeds 500ms for 10
minutes. The east-west budget is deliberately tighter than the 1s edge HTTP
threshold: a single edge request fans out into several internal RPCs, so gRPC
latency compounds into edge P95. This measures the callee's server-side
handling time, not the caller's view — network and caller-side queueing are
on top.

## Impact

Every caller of this service inherits the slowness, and through them the
shopper: a slow inventory answer stretches checkout's availability check, a
slow east-west hop stretches every edge request that fans out through it.
Expect [MicroserviceHighLatencyP95](MicroserviceHighLatencyP95.md) on the
calling services to follow if this persists — this alert firing alone means
you caught the cause before the symptom.

## Diagnosis

### PromQL

```promql
# Alert expr
histogram_quantile(0.95,
  sum by (app, namespace, le) (rate(rpc_server_call_duration_seconds_bucket{app!=""}[5m]))
) > 0.5

# Ready-made P95 + call rate + error rate (recording rules)
app:rpc_server_call_duration_seconds:p95_5m{app="$APP"}
app:rpc_server_call_duration_seconds:rate5m{app="$APP"}
app:rpc_server_call_duration_seconds:error_rate5m{app="$APP"}

# Which RPC is slow?
histogram_quantile(0.95, sum by (rpc_method, le)
  (rate(rpc_server_call_duration_seconds_bucket{app="$APP"}[5m])))

# Is the DB behind the RPC the real culprit?
histogram_quantile(0.95, sum by (app, le)
  (rate(db_client_operation_duration_seconds_bucket{app="$APP"}[5m])))
```

### Grafana

- **Microservices → the service RED board** — did the gRPC P95 move with call
  rate (a caller got chatty) or independently (the handler got slower)?

### kubectl / logs

```bash
APP=<app label>; NS=<namespace label>
kubectl -n "$NS" get pods -l app="$APP"
kubectl top pod -n "$NS" -l app="$APP"     # CPU throttling slows every RPC
```

### VictoriaLogs / traces

Find a slow call in VictoriaLogs (`{app="$APP"}`) and open its `trace_id` in
VictoriaTraces. The server span for the RPC shows where the time went — almost always a
child DB span (`db_client_operation_*` metrics co-moving confirms it) or a
further downstream call.

## Mitigation

Same playbook as [MicroserviceHighLatencyP95](MicroserviceHighLatencyP95.md),
scoped to the gRPC handlers:

1. Identify the slow RPC from the per-`rpc_method` P95 above.
2. If the DB is behind it, follow
   [DBClientQueryP95High](DBClientQueryP95High.md) and check the pgxpool
   alerts — a queued pool acquire lands entirely inside the RPC span.
3. If call rate jumped, find which caller changed (a retry loop or a new
   fan-out) via the caller's traces before scaling the callee.
4. Scale replicas only for genuine CPU saturation on the callee.

## Escalation

Ticket by default. Escalate when the callers start hurting — an edge latency
alert or [MicroserviceHighLatencyP95](MicroserviceHighLatencyP95.md) co-fires
on a calling service, or [GrpcServerHighErrorRate](GrpcServerHighErrorRate.md)
joins in (slowness turning into deadline-exceeded failures). **Do not** raise
caller timeouts to make the symptom disappear — that trades visible errors for
longer shopper waits and hides the regression this alert exists to catch.

## Related

- [MicroserviceHighLatencyP95](MicroserviceHighLatencyP95.md) — the HTTP
  twin; shared cause list and mitigation.
- [GrpcServerHighErrorRate](GrpcServerHighErrorRate.md) — the same handlers
  failing rather than slowing.
- [DBClientQueryP95High](DBClientQueryP95High.md) — the most common span
  hiding inside a slow RPC.

---
_Last updated: 2026-08-19 — rewritten to the canonical template (was a stub)_
