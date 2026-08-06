# MicroserviceLatencyCritical

| | |
|---|---|
| **Severity** | warning (demoted from critical) |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
P95 latency exceeds 2 seconds for 5 minutes.

The name still says "Critical" — that is the threshold tier, not the routing
severity. The alert is a **cause/diagnostic** signal: it fired alongside the
Sloth latency burn-rate page on the same metric, so it was demoted to `warning`
(non-paging on this Alertmanager) and the burn-rate alert remains the page.
Renaming it would break every runbook link and the alert history, so the name
stayed. See [alert catalog — cause-vs-symptom notes](../../alerting/alert-catalog.md#noise--cause-vs-symptom-notes).

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

**Fires when**: P95 latency exceeds 2 seconds for 5 minutes.

**Severity**: critical

When P95 (not just P99) exceeds 2 seconds, the majority of requests are severely slow. This is a widespread performance degradation.

**Escalation**: If DB-related, check `CNPGBlockedQueries` (lock contention) and `PgxPoolNearExhaustion` / `CNPGClusterHighConnectionsWarning` (connection saturation). If not resolved in 15 minutes, scale up replicas as a stopgap.
