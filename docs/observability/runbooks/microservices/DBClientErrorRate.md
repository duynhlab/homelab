# DBClientErrorRate

| | |
|---|---|
| **Severity** | warning |
| **Category** | database |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml` |
| **Metrics** | `db_client_operation_errors_total` (otelpgx) |
| **Status** | active |
| **Dashboard** | Microservices → the service RED board |

## Meaning

`db_client_operation_errors_total` grows faster than 0.1/s for 5 minutes.
otelpgx counts every operation error except `ErrNoRows` — so this is real
failures (SQLSTATE errors, statement timeouts, broken connections), not
"row not found" application flow. The threshold is deliberately low: a healthy
service's DB error rate is effectively zero, so any sustained rate is a signal.

## Impact

The requests behind these operations are failing — DB errors almost always
surface as 5xx at the HTTP layer, so expect `MicroserviceHighErrorRate` to
follow on the same `app` if this persists. The blast radius depends on the
cause: schema drift breaks one query path; a failing Postgres or unhealthy
PgDog pooler breaks every service sharing that database.

## Diagnosis

Likely causes, most common first: Postgres down or failing over, PgDog pooler
unhealthy, statement timeouts, schema drift (SQLSTATE `42xxx`), connection
storms.

### PromQL

```promql
# Alert expr
sum by (app, namespace) (rate(db_client_operation_errors_total{app!=""}[5m])) > 0.1

# Error share of all DB operations — a blip or most of the traffic?
sum by (app) (rate(db_client_operation_errors_total{app="$APP"}[5m]))
  / sum by (app) (rate(db_client_operation_duration_seconds_count{app="$APP"}[5m]))

# One service or every DB client at once? (shared-infra vs app-local cause)
sum by (app) (rate(db_client_operation_errors_total{app!=""}[5m]))
```

### Grafana

- **Microservices → the service RED board** — did the DB errors start with a
  latency or 5xx change, and does the start line up with a deploy?

### kubectl / logs

```bash
APP=<app label>; NS=<namespace label>
kubectl -n "$NS" logs deploy/"$APP" --since=10m | grep -i "sqlstate\|timeout\|conn"
kubectl get cluster -A            # CNPG cluster status — primary healthy?
kubectl -n "$NS" get pods -l app="$APP"
```

### VictoriaLogs / traces

The SQLSTATE is on the query span as the `pgx.sql_state` attribute. Find a
failing request in VictoriaLogs with `{app="$APP"}` filtered to errors, then
open its `trace_id` in VictoriaTraces and read the DB span: `42xxx` is schema drift
(migration mismatch), `57014` is a statement timeout, connection-class errors
point at the pooler or Postgres itself.

## Mitigation

1. If every DB-backed service fires at once, work the shared layer: CNPG
   cluster health (failover in progress?), then PgDog pooler logs. The
   per-service alert is only the messenger there.
2. If one service fires and the SQLSTATE is `42xxx`, the app and its schema
   disagree — check whether the last deploy ran its migration; roll the
   service back by reverting its version pin rather than patching the schema
   by hand.
3. For statement timeouts, treat as a slow-query problem — pivot to
   [DBClientQueryP95High](DBClientQueryP95High.md).

## Escalation

Ticket by default. Escalate to an incident when `MicroserviceHighErrorRate` or
`MicroserviceErrorRateCritical` co-fires on the same `app` (shoppers are
getting 5xx), or when several services fire together (shared database layer).
**Do not** restart the PgDog pooler as a first reflex — it drops every
in-flight connection for every service behind it and can convert one service's
error rate into a platform-wide connection storm.

## Related

- [DBClientQueryP95High](DBClientQueryP95High.md) — the latency face of the
  same otelpgx instrumentation.
- [PgxPoolNearExhaustion](PgxPoolNearExhaustion.md) /
  [PgxPoolAcquireWaitHigh](PgxPoolAcquireWaitHigh.md) — connection storms show
  up there first.
- [MicroserviceHighErrorRate](MicroserviceHighErrorRate.md) — where these
  errors land at the HTTP layer.

---
_Last updated: 2026-08-19 — rewritten to the canonical template (was a stub)_
