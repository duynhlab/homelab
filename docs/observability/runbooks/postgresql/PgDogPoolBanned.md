# PgDogPoolBanned

| | |
|---|---|
| **Severity** | warning |
| **Category** | database |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/pooler/pgdog-alerts.yaml` |
| **Metrics** | `pgdog_banned`, `pgdog_errors` |
| **Status** | active |
| **Validation** | `live-signal` (Kind 2026-10-22: series present with the labels the expr uses; rule healthy, inactive through a PgDog roll) |
| **Dashboard** | Databases → PGDog |
| **Local-stack** | not present locally (no PgDog in local-stack) |

## Meaning

PgDog banned one backend pool of the database after errors (or, for a replica, lag past `ban_replica_lag`). A ban lasts `ban_timeout` (5 minutes) unless the backend recovers.

## Impact

For a replica with read routing, reads fall back to the primary. For the primary, clients of that database cannot get a server connection and fail.

## Diagnosis

### PromQL

```promql
max by (database, role) (pgdog_banned{namespace="product"}) > 0

sum by (database) (increase(pgdog_errors{namespace="product"}[5m]))
```

### kubectl / logs

```bash
DB=<database label>
kubectl -n product get pods -l app.kubernetes.io/name=pgdog
kubectl -n product logs deploy/pgdog-product -c pgdog --since=15m | grep -E "WARN|ERROR" | grep "$DB" | tail -20
```

## Mitigation

1. Find the cause in PgDog's log (connect error, TLS verification, authentication) and check the backend: `kubectl -n product get cluster product-db`, CNPG alerts.
2. A primary ban during a switchover clears once the new primary answers on `product-db-rw`.
3. Do not restart PgDog to clear a ban; it drops every client. The ban expires on its own.

## Escalation

Ticket by default. Treat it as an incident when a service error-rate alert fires for the same database's service.

## Related

- [pooler-operations](../../../databases/runbooks/pooler-operations.md)
- [PgxPoolConnectFailures](../microservices/PgxPoolConnectFailures.md), the client-side view
