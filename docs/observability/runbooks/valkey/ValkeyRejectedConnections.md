# ValkeyRejectedConnections

| | |
|---|---|
| **Severity** | critical |
| **Category** | errors |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/valkey/alerts.yaml` |
| **Metrics** | `redis_rejected_connections_total` |
| **Status** | active |
| **Dashboard** | Cache → Redis |
| **Local-stack** | not alerted locally — compose runs Valkey as `cache` with no redis_exporter and no valkey alert rules |

## Meaning

Fires when **any** connections are rejected in 5 minutes
(`increase(redis_rejected_connections_total[5m]) > 0`, `for: 0m` — immediate).
The `maxclients` limit has been reached; Valkey is turning new clients away.

## Impact

For the rejected clients the cache is effectively unavailable — their lookups
fail over to PostgreSQL, so product-service (the primary client) sees extra DB
load and latency. Because the count only has to exceed zero, this fires on the
first rejection, before the impact is widespread.

## Diagnosis

### PromQL

```promql
increase(redis_rejected_connections_total[5m]) > 0
```

Confirm the connection count against the limit:

```promql
redis_connected_clients
```

### kubectl / logs

```bash
POD=$(kubectl get pod -n cache-system -l app.kubernetes.io/name=valkey -o name | head -1)
kubectl exec -n cache-system $POD -- valkey-cli INFO clients
kubectl exec -n cache-system $POD -- valkey-cli CLIENT LIST | wc -l
```

## Mitigation

1. Increase the `maxclients` configuration (Valkey Helm values) to restore
   service while the root cause is found.
2. Fix connection leaks — see
   [ValkeyHighClientConnections](ValkeyHighClientConnections.md).
3. Check whether a burst of new pod replicas (deploy, HPA scale-up)
   overwhelmed the connection limit.

## Escalation

Incident if rejections continue or product latency alerts
(`MicroserviceHighLatency*`) co-fire; a single transient rejection during a
deploy burst can stay a ticket with a leak follow-up. Do **not** restart
Valkey to clear connections — the reconnect stampede plus a cold cache makes
the rejection storm worse.

## Related

- [ValkeyHighClientConnections](ValkeyHighClientConnections.md) — the warning
  stage; usually fires first and names the leaking client.
- Cache-miss impact lands on product latency (`MicroserviceHighLatency*`).

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the valkey/ domain folder_
