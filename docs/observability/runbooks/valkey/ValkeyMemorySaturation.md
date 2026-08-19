# ValkeyMemorySaturation

| | |
|---|---|
| **Severity** | warning |
| **Category** | saturation |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/valkey/alerts.yaml` |
| **Metrics** | `redis_memory_used_bytes`, `redis_memory_max_bytes` |
| **Status** | active |
| **Dashboard** | Cache → Redis |
| **Local-stack** | not alerted locally — compose runs Valkey as `cache` with no redis_exporter and no valkey alert rules |

## Meaning

Fires when memory usage exceeds **90% of maxmemory** for **5 minutes**
(`redis_memory_used_bytes / redis_memory_max_bytes > 0.9`, only where
`redis_memory_max_bytes > 0`). The cache is approaching its configured ceiling;
under `allkeys-lru` evictions may start soon.

## Impact

Not yet an outage — this is the early warning. Once evictions start, the
working set shrinks, the hit ratio drops, and product-service (the primary
client) falls through to PostgreSQL more often, raising DB load and latency.

## Diagnosis

### PromQL

```promql
redis_memory_used_bytes / redis_memory_max_bytes > 0.9
and redis_memory_max_bytes > 0
```

Drill-down — current ratio and whether evictions already started:

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

1. Increase `maxmemory` in the Valkey Helm values.
2. Review key TTLs: shorten TTLs for less critical data.
3. Check the eviction policy (`allkeys-lru` recommended for the cache use
   case) — do not switch it to a `noeviction` variant casually.

## Escalation

Ticket for capacity tuning. Page only if it escalates to
[ValkeyMemorySaturationCritical](ValkeyMemorySaturationCritical.md) or
product latency alerts (`MicroserviceHighLatency*`) co-fire. Do **not**
`FLUSHALL` to free memory — that trades a saturation warning for a cold cache
and a guaranteed DB load spike.

## Related

- [ValkeyMemorySaturationCritical](ValkeyMemorySaturationCritical.md) — the
  95% escalation of this alert.
- [ValkeyHighEvictionRate](ValkeyHighEvictionRate.md) — the symptom that
  follows sustained saturation.
- Cache-miss impact lands on product latency (`MicroserviceHighLatency*`).

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the valkey/ domain folder_
