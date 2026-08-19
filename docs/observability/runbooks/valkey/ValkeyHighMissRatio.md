# ValkeyHighMissRatio

| | |
|---|---|
| **Severity** | warning |
| **Category** | errors |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/valkey/alerts.yaml` |
| **Metrics** | `redis_keyspace_misses_total`, `redis_keyspace_hits_total` |
| **Status** | active |
| **Dashboard** | Cache → Redis |
| **Local-stack** | not alerted locally — compose runs Valkey as `cache` with no redis_exporter and no valkey alert rules |

## Meaning

Fires when the cache miss ratio exceeds **50% for 10 minutes** — more than
half of lookups are misses. Not always an incident: a fresh restart warms up
through exactly this state.

## Impact

The cache is ineffective: every miss is a PostgreSQL round-trip, so DB load
and product-path latency rise for product-service, the primary client. The
consequence surfaces as `MicroserviceHighLatency*` rather than as a hard
failure.

## Diagnosis

Possible causes:

- Cache warming not complete after restart
- Key TTLs too short
- Application querying keys that were never cached
- Evictions removing frequently accessed keys

### PromQL

```promql
rate(redis_keyspace_misses_total[5m])
/ (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))
> 0.5
```

Hit ratio (the inverse view):

```promql
rate(redis_keyspace_hits_total[5m])
/ (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))
```

### kubectl / logs

```bash
POD=$(kubectl get pod -n cache-system -l app.kubernetes.io/name=valkey -o name | head -1)
kubectl exec -n cache-system $POD -- valkey-cli INFO stats
```

## Mitigation

1. If after a restart: wait for the cache to warm up.
2. Increase TTLs for frequently accessed keys.
3. Check that the Cache-Aside pattern is correctly implemented in application
   code (product-service repo).

## Escalation

Ticket — unless product latency alerts (`MicroserviceHighLatency*`) co-fire,
which makes it an incident on the product path. If the cause is application
code, route the fix to the product-service repo, not homelab. Do **not**
restart Valkey to "reset" the ratio — that guarantees a 100% miss ratio while
it re-warms.

## Related

- [ValkeyHighEvictionRate](ValkeyHighEvictionRate.md) — evictions removing hot
  keys is one cause of a rising miss ratio.
- Cache-miss impact lands on product latency (`MicroserviceHighLatency*`).

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the valkey/ domain folder_
