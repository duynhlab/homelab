# MicroserviceLatencyCritical

| | |
|---|---|
| **Severity** | critical |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
P95 latency exceeds 2 seconds for 5 minutes.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

**Fires when**: P95 latency exceeds 2 seconds for 5 minutes.

**Severity**: critical

When P95 (not just P99) exceeds 2 seconds, the majority of requests are severely slow. This is a widespread performance degradation.

**Escalation**: If DB-related, check `CNPGBlockedQueries` (lock contention) and `PgxPoolNearExhaustion` / `CNPGClusterHighConnectionsWarning` (connection saturation). If not resolved in 15 minutes, scale up replicas as a stopgap.
