# ValkeyHighClientConnections

| | |
|---|---|
| **Severity** | warning |
| **Category** | saturation |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/valkey/alerts.yaml` |
| **Metrics** | `redis_connected_clients` |
| **Status** | active |
| **Dashboard** | Cache → Redis |
| **Local-stack** | not alerted locally — compose runs Valkey as `cache` with no redis_exporter and no valkey alert rules |

## Meaning

Fires when connected clients exceed **100 for 5 minutes**
(`redis_connected_clients > 100`). For a single-node cache serving mainly
product-service, that count usually means clients are being opened and not
returned to the pool — a leak — rather than legitimate growth.

## Impact

Headroom toward the `maxclients` limit is being consumed. If it keeps
climbing, Valkey starts rejecting new connections
([ValkeyRejectedConnections](ValkeyRejectedConnections.md)) and cache lookups
fail over to PostgreSQL. On its own this alert is early warning, not yet
user-visible.

## Diagnosis

### PromQL

```promql
redis_connected_clients > 100
```

Trend — leak (steady climb) vs burst (step change on deploy):

```promql
redis_connected_clients
```

### kubectl / logs

```bash
POD=$(kubectl get pod -n cache-system -l app.kubernetes.io/name=valkey -o name | head -1)
kubectl exec -n cache-system $POD -- valkey-cli CLIENT LIST | wc -l
kubectl exec -n cache-system $POD -- valkey-cli INFO clients
```

`CLIENT LIST` shows source addresses — map them to pods to name the leaking
service.

## Mitigation

1. Check for connection leaks in application code (connections not being
   returned to the pool).
2. Tune connection pool settings in the microservices (service repos).
3. Increase `maxclients` only if the connection count is legitimately needed.

## Escalation

Ticket to the owning service repo once `CLIENT LIST` names the leaker; page
only if [ValkeyRejectedConnections](ValkeyRejectedConnections.md) starts
co-firing. Do **not** raise `maxclients` as the first move — it hides the
leak until the pod runs out of file descriptors instead.

## Related

- [ValkeyRejectedConnections](ValkeyRejectedConnections.md) — what this alert
  becomes if the climb continues to `maxclients`.
- Cache-miss impact lands on product latency (`MicroserviceHighLatency*`).

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the valkey/ domain folder_
