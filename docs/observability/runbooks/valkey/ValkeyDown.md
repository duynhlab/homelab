# ValkeyDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | availability |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/valkey/alerts.yaml` |
| **Metrics** | `redis_up` (redis_exporter) |
| **Status** | active |
| **Dashboard** | Cache → Redis |
| **Local-stack** | not alerted locally — compose runs Valkey as `cache` with no redis_exporter and no valkey alert rules |

## Meaning

Fires when `redis_up == 0` for **1 minute** — the redis_exporter cannot reach
the Valkey instance. Either the pod is down/crashlooping or the exporter's
connection to it is broken; both mean the platform cache is unreachable.

## Impact

Cache-Aside falls through to PostgreSQL for all cached endpoints
(product-service is the primary client). Reads are fail-open, so this shows up
as increased database load and latency on product paths, not hard availability
loss — but a sustained outage risks `MicroserviceHighLatency*` and DB
saturation alerts following.

## Diagnosis

### PromQL

```promql
redis_up == 0
```

### kubectl / logs

```bash
kubectl get pods -n cache-system
kubectl describe pod -n cache-system -l app.kubernetes.io/name=valkey
kubectl logs -n cache-system -l app.kubernetes.io/name=valkey --tail=100
```

## Mitigation

1. Check pod events for OOM or scheduling issues (`kubectl describe` above).
2. Verify the PVC is bound if persistence is enabled.
3. Check HelmRelease status: `kubectl get helmrelease -n cache-system`.

## Escalation

**Page.** The platform's only cache is unreachable and DB load is climbing
while it stays down. It remains an incident until `redis_up == 1` again.
Do **not** "fix" it by scaling product-service replicas — that multiplies the
DB fallthrough load instead of restoring the cache.

## Related

Watch `MicroserviceHighLatency*` on product-service — cache-miss impact lands
there. Recent-changes check when config drift is plausible:

```bash
git log --oneline -5 -- kubernetes/infra/controllers/caching/valkey/
```

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the valkey/ domain folder_
