# ValkeyMemorySaturationCritical

| | |
|---|---|
| **Severity** | critical |
| **Category** | saturation |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/valkey/alerts.yaml` |
| **Metrics** | `redis_memory_used_bytes`, `redis_memory_max_bytes` |
| **Status** | active |
| **Dashboard** | Cache → Redis |
| **Local-stack** | not alerted locally — compose runs Valkey as `cache` with no redis_exporter and no valkey alert rules |

## Meaning

Fires when memory usage exceeds **95% of maxmemory** for **2 minutes**
(`redis_memory_used_bytes / redis_memory_max_bytes > 0.95`, only where
`redis_memory_max_bytes > 0`) — the escalation of
[ValkeyMemorySaturation](ValkeyMemorySaturation.md). Evictions are likely
already active.

## Impact

At 95% mass evictions are imminent or underway: cache hit-rate collapse
followed by a DB load spike as product-service (the primary client) falls
through to PostgreSQL. If the eviction policy is not `allkeys-lru`, writes can
start erroring instead of degrading.

## Diagnosis

### PromQL

```promql
redis_memory_used_bytes / redis_memory_max_bytes > 0.95
and redis_memory_max_bytes > 0
```

Same drill-downs as [ValkeyMemorySaturation](ValkeyMemorySaturation.md):

```promql
redis_memory_used_bytes / redis_memory_max_bytes

rate(redis_evicted_keys_total[5m])
```

### kubectl / logs

```bash
POD=$(kubectl get pod -n cache-system -l app.kubernetes.io/name=valkey -o name | head -1)
kubectl exec -n cache-system $POD -- valkey-cli INFO memory
```

## Mitigation

1. Raise `maxmemory` now (Valkey Helm values) — this is the fast, reversible
   fix.
2. Or flush low-value key patterns (targeted `DEL`/`UNLINK`, never a blanket
   flush).
3. Verify the eviction policy is `allkeys-lru` so the instance degrades
   instead of erroring on writes.

## Escalation

Incident if product latency alerts (`MicroserviceHighLatency*`) or
[ValkeyHighEvictionRate](ValkeyHighEvictionRate.md) co-fire; otherwise an
urgent ticket — the fail-open design buys time but not much. Do **not**
restart the pod to "clear memory": you lose the entire working set and start
cold at the moment DB load is already elevated.

## Related

- [ValkeyMemorySaturation](ValkeyMemorySaturation.md) — the 90% warning stage.
- [ValkeyHighEvictionRate](ValkeyHighEvictionRate.md) — confirms evictions are
  active.
- Cache-miss impact lands on product latency (`MicroserviceHighLatency*`).

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the valkey/ domain folder_
