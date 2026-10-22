# PgDogCheckoutTimeouts

| | |
|---|---|
| **Severity** | warning |
| **Category** | database |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/pooler/pgdog-alerts.yaml` |
| **Metrics** | `pgdog_total_checkout_timeouts`, `pgdog_cl_waiting` |
| **Status** | active |
| **Validation** | `static-valid` (2026-10-22, #1350) |
| **Dashboard** | Databases → PGDog |
| **Local-stack** | not present locally (no PgDog in local-stack) |

## Meaning

A client of the database gave up waiting for a server connection after `checkout_timeout` (5 s). Each timeout is a failed request. With passthrough auth, a client whose password PostgreSQL refuses also ends here after 5 s.

## Impact

Requests to the service fail; the client sees a timeout or an authentication error.

## Diagnosis

### PromQL

```promql
sum by (database) (increase(pgdog_total_checkout_timeouts{namespace="product"}[5m])) > 0

# Was the pool full (queueing) or is it authentication?
max by (database) (pgdog_cl_waiting{namespace="product"})
```

### kubectl / logs

```bash
DB=<database label>
kubectl -n product get pods -l app.kubernetes.io/name=pgdog
kubectl -n product logs deploy/pgdog-product -c pgdog --since=15m | grep -E "WARN|ERROR" | grep "$DB" | tail -20
```

## Mitigation

1. If clients were queueing, follow [PgDogClientsWaiting](PgDogClientsWaiting.md).
2. If not, look for `password ... is wrong` in PgDog's log: the client holds a stale password. Compare the ESO Secret with the pod's mounted file by hash ([rotate-cnpg-service-password](../../../databases/runbooks/rotate-cnpg-service-password.md)); `PgxPoolConnectFailures{error_type="28P01"}` should fire on the client side too.

## Escalation

Ticket by default. Treat it as an incident when a service error-rate alert fires for the same database's service.

## Related

- [pooler-operations](../../../databases/runbooks/pooler-operations.md)
- [PgxPoolConnectFailures](../microservices/PgxPoolConnectFailures.md), the client-side view
