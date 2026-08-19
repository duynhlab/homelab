# Valkey Alert Runbooks

Per-alert investigation guides for the platform's only cache — the single-node
Valkey instance in `cache-system`. Product-service is the primary client
(Cache-Aside, fail-open): a cache problem shows up as PostgreSQL load and
product-path latency, not hard downtime. One file per alert name.

| Quick facts | |
|---|---|
| Alert rules | [`prometheusrules/valkey/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/valkey/alerts.yaml) |
| Alert catalog | [§3 Valkey cache](../../alerting/alert-catalog.md#3-valkey-cache) |
| Platform hub | [docs/caching/README.md](../../../caching/README.md) |
| App contract | [docs/api/caching.md](../../../api/caching.md) |

## Index

| Alert | Sev | Source | Status | Runbook |
|-------|-----|--------|--------|---------|
| ValkeyDown | critical | homelab | active | [ValkeyDown.md](ValkeyDown.md) |
| ValkeyMemorySaturation | warning | homelab | active | [ValkeyMemorySaturation.md](ValkeyMemorySaturation.md) |
| ValkeyMemorySaturationCritical | critical | homelab | active | [ValkeyMemorySaturationCritical.md](ValkeyMemorySaturationCritical.md) |
| ValkeyHighEvictionRate | warning | homelab | active | [ValkeyHighEvictionRate.md](ValkeyHighEvictionRate.md) |
| ValkeyHighMissRatio | warning | homelab | active | [ValkeyHighMissRatio.md](ValkeyHighMissRatio.md) |
| ValkeyHighClientConnections | warning | homelab | active | [ValkeyHighClientConnections.md](ValkeyHighClientConnections.md) |
| ValkeyRejectedConnections | critical | homelab | active | [ValkeyRejectedConnections.md](ValkeyRejectedConnections.md) |

## Domain specifics

- **Diagnosis dialect:** start with the `redis_*` exporter metrics via PromQL
  (redis_exporter scraped through the Valkey chart ServiceMonitor), then drop
  to `kubectl exec -n cache-system $POD -- valkey-cli ...` (`INFO memory`,
  `INFO clients`, `CLIENT LIST`) only when the metric cannot name the culprit.
- **Dashboard:** Cache → Redis (the redis_exporter board).
- **Local-stack divergence:** the compose stack runs Valkey as the `cache`
  service with no redis_exporter and no valkey alert rules, so none of these
  alerts exist locally.

## Template

New runbooks follow [`_TEMPLATE.md`](../_TEMPLATE.md) (Meaning → Impact →
Diagnosis → Mitigation → Escalation).

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the valkey/ domain folder_
