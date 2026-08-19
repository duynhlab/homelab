# ValkeyHighEvictionRate

| | |
|---|---|
| **Severity** | warning |
| **Category** | saturation |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/valkey/alerts.yaml` |
| **Metrics** | `redis_evicted_keys_total` |
| **Status** | active |
| **Dashboard** | Cache → Redis |
| **Local-stack** | not alerted locally — compose runs Valkey as `cache` with no redis_exporter and no valkey alert rules |

## Meaning

Fires when the eviction rate exceeds **100 keys/sec for 10 minutes**
(`rate(redis_evicted_keys_total[5m]) > 100`). The cache is under sustained
memory pressure and `allkeys-lru` is discarding the working set to make room.

## Impact

Frequently accessed keys get evicted and immediately re-fetched from
PostgreSQL — repeated DB fetches and a degraded hit ratio for product-service,
the primary client. Latency rises on cached product paths; the cache is
churning rather than serving.

## Diagnosis

### PromQL

```promql
rate(redis_evicted_keys_total[5m]) > 100
```

Confirm memory pressure is the driver:

```promql
redis_memory_used_bytes / redis_memory_max_bytes
```

### kubectl / logs

```bash
POD=$(kubectl get pod -n cache-system -l app.kubernetes.io/name=valkey -o name | head -1)
kubectl exec -n cache-system $POD -- valkey-cli INFO memory
kubectl exec -n cache-system $POD -- valkey-cli INFO stats
```

## Mitigation

1. Increase `maxmemory` to reduce eviction pressure (Valkey Helm values).
2. Audit cache key patterns: are large or unnecessary keys consuming space?
3. Consider adding a second Valkey instance for hot key isolation.

## Escalation

Ticket for capacity/key-pattern work; page only if product latency alerts
(`MicroserviceHighLatency*`) co-fire — evictions alone are the cache doing its
job under pressure. Do **not** shorten TTLs across the board as a quick fix:
that raises the miss ratio and shifts even more load to PostgreSQL.

## Related

- [ValkeyMemorySaturation](ValkeyMemorySaturation.md) /
  [ValkeyMemorySaturationCritical](ValkeyMemorySaturationCritical.md) — the
  memory pressure that causes this alert.
- [ValkeyHighMissRatio](ValkeyHighMissRatio.md) — the downstream symptom when
  evictions remove hot keys.
- Cache-miss impact lands on product latency (`MicroserviceHighLatency*`).

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the valkey/ domain folder_
