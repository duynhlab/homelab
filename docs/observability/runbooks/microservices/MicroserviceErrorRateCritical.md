# MicroserviceErrorRateCritical

| | |
|---|---|
| **Severity** | critical |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
5xx error rate exceeds 15% of total traffic for 5 minutes.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

**Fires when**: 5xx error rate exceeds 15% of total traffic for 5 minutes.

**Severity**: critical

Same investigation as `MicroserviceHighErrorRate` but with higher urgency. At 15% error rate, a significant portion of users are impacted.

**Escalation**: If not identified within 10 minutes, consider rolling back the most recent deployment.
