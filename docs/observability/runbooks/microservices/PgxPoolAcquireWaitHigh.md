# PgxPoolAcquireWaitHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | database |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml` |
| **Metrics** | `pgxpool_empty_acquire_total` (pgxpool stats via the otelpgx pipeline) |
| **Status** | active |
| **Dashboard** | Microservices → the service RED board |

## Meaning

`pgxpool_empty_acquire_total` counts acquires that found the pool empty and had
to wait for a free connection. More than 1/s of them for 10 minutes means the
pool is contended — the earliest saturation signal, usually before
`PgxPoolNearExhaustion` reports the pool pinned at its ceiling. A short burst
during a traffic spike is normal; the 10-minute debounce means this fires only
on sustained contention.

## Impact

Every blocked acquire adds its wait time to a shopper request — DB latency the
server never sees, because the query has not started yet. Left alone this
becomes visible P95/P99 growth and, at the hard ceiling, timeouts. Impact is
conditional: brief waits under load are absorbed; sustained waits mean the pool
is undersized for current traffic or queries are holding connections too long.

## Diagnosis

### PromQL

```promql
# Alert expr
sum by (app, namespace) (rate(pgxpool_empty_acquire_total{app!=""}[5m])) > 1

# Mean wait per blocked acquire (nanoseconds) — is the wait trivial or painful?
rate(pgxpool_empty_acquire_wait_time_nanoseconds_total{app="$APP"}[5m])
  / rate(pgxpool_empty_acquire_total{app="$APP"}[5m])

# Pool headroom — is this contention or already near exhaustion?
sum by (app) (pgxpool_acquired_connections{app="$APP"})
  / sum by (app) (pgxpool_max_connections{app="$APP"})

# Did query latency rise first? (queries holding conns longer)
histogram_quantile(0.95, sum by (app, le)
  (rate(db_client_operation_duration_seconds_bucket{app="$APP", pgx_operation_type="query"}[5m])))
```

### Grafana

- **Microservices → the service RED board** — did traffic grow with the waits
  (undersized pool) or did query latency grow without traffic (slow queries)?

### kubectl / logs

```bash
APP=<app label>; NS=<namespace label>
kubectl -n "$NS" get pods -l app="$APP"          # replica count vs usual
kubectl -n "$NS" logs deploy/"$APP" --since=15m | grep -i "acquire\|timeout"
```

## Mitigation

Same remediation fork as [PgxPoolNearExhaustion](PgxPoolNearExhaustion.md):

1. If query P95 rose first, fix the queries — the pool is the victim, not the
   cause. Pivot into the slow query via `DBClientQueryP95High` diagnosis.
2. If latency is flat but traffic grew, grow the pool (`MaxConnections` in the
   service config) — but check the Postgres/PgDog side has headroom first; the
   sum of every service's pool must fit under the server connection budget.
3. Check for a connection leak (missing `Rows.Close`) if acquired connections
   climb without matching traffic.

## Escalation

Ticket by default — this is the early-warning tier. Treat it as an incident
only when [PgxPoolNearExhaustion](PgxPoolNearExhaustion.md) or a service
latency alert (`MicroserviceHighLatencyP95`/`P99`) co-fires on the same `app`:
that means shoppers are already waiting. **Do not** bounce the pods to "reset"
the pool — a restart empties the pool, briefly clears the metric, and hides
the trend you need; and do not raise `MaxConnections` casually without
checking the Postgres-side ceiling.

## Related

- [PgxPoolNearExhaustion](PgxPoolNearExhaustion.md) — the next stage: pool
  pinned ≥80% of max.
- [DBClientQueryP95High](DBClientQueryP95High.md) — slow queries are the most
  common root cause of pool waits.

```bash
git log --oneline -5 -- kubernetes/apps/services/
```

---
_Last updated: 2026-08-19 — rewritten to the canonical template (was a stub)_
