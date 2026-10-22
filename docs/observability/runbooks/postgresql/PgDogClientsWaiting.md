# PgDogClientsWaiting

| | |
|---|---|
| **Severity** | warning |
| **Category** | database |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/pooler/pgdog-alerts.yaml` |
| **Metrics** | `pgdog_cl_waiting`, `pgdog_sv_active`, `pgdog_maxwait` |
| **Status** | active |
| **Validation** | `static-valid` (2026-10-22, #1350) |
| **Dashboard** | Databases → PGDog |
| **Local-stack** | not present locally (no PgDog in local-stack) |

## Meaning

Clients of one database have queued in PgDog for 5 minutes waiting for a server connection. Each database has a pool of 30 server connections (`poolSize`) per PgDog pod, in transaction mode; clients wait when every one is busy with a transaction.

## Impact

Every waiting client adds its wait to a request. Past `checkout_timeout` (5 s) the client gets an error, which raises `PgDogCheckoutTimeouts`.

## Diagnosis

### PromQL

```promql
max by (database) (pgdog_cl_waiting{namespace="product"}) > 0

# Pool use vs size, per pod
sum by (pod, database) (pgdog_sv_active{namespace="product"})
# Longest wait (seconds)
max by (database) (pgdog_maxwait{namespace="product"})
```

### kubectl / logs

```bash
DB=<database label>
kubectl -n product get pods -l app.kubernetes.io/name=pgdog
kubectl -n product logs deploy/pgdog-product -c pgdog --since=15m | grep -E "WARN|ERROR" | grep "$DB" | tail -20
```

## Mitigation

1. Slow transactions hold server connections: check `DBClientQueryP95High` for the service and long-running queries on `product-db` (`pg_stat_activity`).
2. A client pool larger than PgDog's pool only moves the queue: compare the service's `DB_POOL_MAX_CONNECTIONS` (×replicas) with `poolSize`.
3. Raise `poolSize` in the PgDog HelmRelease only after confirming PostgreSQL has connection headroom (`CNPGClusterHighConnectionsWarning`).

## Escalation

Ticket by default. Treat it as an incident when a service error-rate alert fires for the same database's service.

## Related

- [pooler-operations](../../../databases/runbooks/pooler-operations.md)
- [PgxPoolConnectFailures](../microservices/PgxPoolConnectFailures.md), the client-side view
