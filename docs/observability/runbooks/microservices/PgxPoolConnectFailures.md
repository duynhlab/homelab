# PgxPoolConnectFailures

| | |
|---|---|
| **Severity** | warning |
| **Category** | database |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml` |
| **Metrics** | `pgx_pool_connect_failures_total{error_type}` (pkg/dbx ≥ v0.39.0) |
| **Status** | active |
| **Dashboard** | Microservices → the service RED board |

## Meaning

`pkg/dbx` counts every connection its pool fails to open. `error_type` holds the
SQLSTATE the server answered with, or `connect` when there was no answer (dial
error, TLS error or timeout). pgxpool never retries a failed connect: the
request that needed the connection fails at once. This counter is the only
signal of it, apart from the request errors.

A password rotation is expected to produce a short burst of `28P01`. After
OpenBAO changes the role's password, a new connection fails until the kubelet
updates the pod's password file; that window was measured at about a minute
(see [rotate-cnpg-service-password](../../../databases/runbooks/rotate-cnpg-service-password.md#how-a-rotation-propagates)).
The alert waits for failures in every 5-minute window for 10 minutes, so a
rotation burst does not fire it. A sustained failure means the pod cannot log
in at all.

## Impact

Pooled connections keep working, so a service with a warm pool can look
healthy until it needs one more connection: after a scale-up, a pod restart or
a `MaxConnLifetime` recycle (30 min). Each failed connect fails the request
that triggered it. A pod whose pool drains to zero cannot serve database
traffic at all.

## Diagnosis

### PromQL

```promql
# Alert expr
sum by (app, namespace, error_type) (increase(pgx_pool_connect_failures_total{app!=""}[5m])) > 0

# Which pods? A single pod points at its mount; all pods point at the role or the pooler
sum by (pod, error_type) (increase(pgx_pool_connect_failures_total{app="$APP"}[5m]))

# Is the pool still serving from existing connections?
sum by (pod) (pgxpool_total_connections{app="$APP"})
```

### By `error_type`

| error_type | Meaning | Check |
|---|---|---|
| `28P01` | The password in the pod's file is not the role's password | Compare hashes, never values: the ESO Secret in the service namespace and `/etc/db/secret/password` in the pod |
| `57P01` | The pooler or server is shutting down | A PgDog or PgBouncer rollout that does not finish: `kubectl -n product get pods -l app.kubernetes.io/name=pgdog` |
| `53300` | Too many connections | Pooler or server connection limit; see [PgxPoolNearExhaustion](PgxPoolNearExhaustion.md) for the pool side |
| `connect` | No answer: dial, TLS or timeout | NetworkPolicy, pooler `Ready`, and `make db-tls` for certificate trust |

### kubectl

```bash
APP=<app label>; NS=<namespace label>
kubectl -n "$NS" logs deploy/"$APP" --since=15m | grep -E "28P01|57P01|53300|connect"
# Password hashes: Secret vs the file the pod reads (prints 12 hex chars only)
kubectl -n "$NS" get secret <cluster>-"$APP"-runtime-secret -o jsonpath='{.data.password}' | base64 -d | sha256sum | cut -c1-12
kubectl -n "$NS" exec deploy/"$APP" -c "$APP" -- cat /etc/db/secret/password | sha256sum | cut -c1-12
```

## Mitigation

1. **`28P01`, Secret and file differ:** the kubelet has not synced the volume.
   Wait one sync period. If the file never changes, restart the deployment so
   it mounts the current Secret.
2. **`28P01`, Secret and file match:** the role's password differs from the
   one OpenBAO handed out. Rotate the role again with `rotate-role`; see
   [rotate-cnpg-service-password](../../../databases/runbooks/rotate-cnpg-service-password.md#force-a-rotation).
3. **`57P01` or `connect`:** fix the pooler first
   ([pooler-operations](../../../databases/runbooks/pooler-operations.md)). The
   pool reconnects by itself once the pooler accepts logins.

## Escalation

Ticket by default. Treat it as an incident when `DBClientErrorRate` or a
service error-rate alert co-fires on the same `app`, because requests are
already failing. **Do not** print or paste the password to compare it; compare
hashes.

## Related

- [PgxPoolNearExhaustion](PgxPoolNearExhaustion.md), [PgxPoolAcquireWaitHigh](PgxPoolAcquireWaitHigh.md)
  are the other pool-health alerts.
- [DBClientErrorRate](DBClientErrorRate.md) covers query errors on connections
  that did open.
