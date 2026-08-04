# Microservices Application Alert Runbooks

Per-alert investigation guides for OTLP-based RED/Golden Signal alerts on the
10 cluster-deployed Go microservices. One file per alert name.

| Quick facts | |
|---|---|
| Alert rules | [`prometheusrules/microservices/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |
| Recording rules | [`prometheusrules/microservices/recording-rules.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/recording-rules.yaml) |
| Metrics reference | [`metrics-apps.md`](../../metrics/metrics-apps.md) |
| Alert catalog | [§1 Microservices](../../alerting/alert-catalog.md#1-microservices-red-metrics) |
| Hub (workflows, tuning) | [`../microservices-alerts.md`](../microservices-alerts.md) |

## Index

| Alert | Sev | Category | Runbook |
|-------|-----|----------|---------|
| MicroserviceDown | critical | availability | [MicroserviceDown.md](MicroserviceDown.md) |
| KubeStateMetricsAbsent | critical | observability | [KubeStateMetricsAbsent.md](KubeStateMetricsAbsent.md) |
| MicroserviceAllInstancesDown | critical | availability | [MicroserviceAllInstancesDown.md](MicroserviceAllInstancesDown.md) |
| OtelMetricsPipelineExportFailures | critical | availability | [OtelMetricsPipelineExportFailures.md](OtelMetricsPipelineExportFailures.md) |
| MicroserviceHighErrorRate | warning | errors | [MicroserviceHighErrorRate.md](MicroserviceHighErrorRate.md) |
| MicroserviceErrorRateCritical | critical | errors | [MicroserviceErrorRateCritical.md](MicroserviceErrorRateCritical.md) |
| MicroserviceNoSuccessfulRequests | critical | errors | [MicroserviceNoSuccessfulRequests.md](MicroserviceNoSuccessfulRequests.md) |
| GrpcServerHighErrorRate | warning | errors | [GrpcServerHighErrorRate.md](GrpcServerHighErrorRate.md) |
| MicroserviceHighLatencyP95 | warning | latency | [MicroserviceHighLatencyP95.md](MicroserviceHighLatencyP95.md) |
| MicroserviceHighLatencyP99 | warning | latency | [MicroserviceHighLatencyP99.md](MicroserviceHighLatencyP99.md) |
| MicroserviceLatencyCritical | critical | latency | [MicroserviceLatencyCritical.md](MicroserviceLatencyCritical.md) |
| GrpcServerHighLatencyP95 | warning | latency | [GrpcServerHighLatencyP95.md](GrpcServerHighLatencyP95.md) |
| MicroserviceNoTraffic | warning | traffic | [MicroserviceNoTraffic.md](MicroserviceNoTraffic.md) |
| MicroserviceApdexCritical | critical | traffic | [MicroserviceApdexCritical.md](MicroserviceApdexCritical.md) |
| MicroserviceGoroutineLeak | warning | runtime | [MicroserviceGoroutineLeak.md](MicroserviceGoroutineLeak.md) |
| MicroserviceHighMemoryUsage | warning | runtime | [MicroserviceHighMemoryUsage.md](MicroserviceHighMemoryUsage.md) |
| DBClientQueryP95High | warning | database | [DBClientQueryP95High.md](DBClientQueryP95High.md) |
| DBClientErrorRate | warning | database | [DBClientErrorRate.md](DBClientErrorRate.md) |
| PgxPoolNearExhaustion | warning | database | [PgxPoolNearExhaustion.md](PgxPoolNearExhaustion.md) |
| PgxPoolAcquireWaitHigh | warning | database | [PgxPoolAcquireWaitHigh.md](PgxPoolAcquireWaitHigh.md) |

### RFC-0021 stock migration (write path)

Rules: [`prometheusrules/microservices/rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) ·
catalog: [§9 RFC-0021 overhaul](../../alerting/alert-catalog.md#9-rfc-0021-overhaul-stock-migration)

These cover a failure class the RED alerts above cannot see: an order and its stock
can disagree while every service reports perfectly healthy.

| Alert | Sev | Category | Runbook |
|-------|-----|----------|---------|
| OrderReconcilerInvariantBreach | critical | correctness | [OrderReconcilerInvariantBreach.md](OrderReconcilerInvariantBreach.md) |
| FulfillmentStartOutboxStalled | critical | availability | [FulfillmentStartOutboxStalled.md](FulfillmentStartOutboxStalled.md) |
| FulfillmentStartOutboxFailed | critical | correctness | [FulfillmentStartOutboxFailed.md](FulfillmentStartOutboxFailed.md) |
| OrderSagaCompensationFailing | critical | correctness | [OrderSagaCompensationFailing.md](OrderSagaCompensationFailing.md) |
| OrderSagaNotCompleting | critical | availability | [OrderSagaNotCompleting.md](OrderSagaNotCompleting.md) |
| OrderReconcilerBacklogNotDraining | warning | database | [OrderReconcilerBacklogNotDraining.md](OrderReconcilerBacklogNotDraining.md) |
| OrderReconcilerBacklogUnreadable | warning | observability | [OrderReconcilerBacklogUnreadable.md](OrderReconcilerBacklogUnreadable.md) |
| OrderReconcilerDependencyUnreadable | warning | availability | [OrderReconcilerDependencyUnreadable.md](OrderReconcilerDependencyUnreadable.md) |
| OrderReconcilerPassTruncated | warning | correctness | [OrderReconcilerPassTruncated.md](OrderReconcilerPassTruncated.md) |
| OrderParticipantDisagreement | warning | correctness | [OrderParticipantDisagreement.md](OrderParticipantDisagreement.md) |
| OrderStartParticipantUnrecognised | warning | correctness | [OrderStartParticipantUnrecognised.md](OrderStartParticipantUnrecognised.md) |
| OrderInventoryCommitLagHigh | warning | latency | [OrderInventoryCommitLagHigh.md](OrderInventoryCommitLagHigh.md) |

### RFC-0021 phase 5 (order aggregate)

Rules: [`prometheusrules/microservices/rfc0021-phase5.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase5.yaml) ·
catalog: [§9 RFC-0021 overhaul](../../alerting/alert-catalog.md#9-rfc-0021-overhaul-stock-migration)

Two order states mean **somebody is owed work**, and neither is visible to a RED
alert: the order is not erroring, it is waiting.

| Alert | Sev | Category | Runbook |
|-------|-----|----------|---------|
| OrderStuckCancelling | critical | correctness | [OrderStuckCancelling.md](OrderStuckCancelling.md) |
| OrderManualReviewBacklog | warning | correctness | [OrderManualReviewBacklog.md](OrderManualReviewBacklog.md) |
| OrderCancellationOutboxStalled | warning | availability | [OrderCancellationOutboxStalled.md](OrderCancellationOutboxStalled.md) |
| OrderProjectionWritesFailing | warning | observability | [OrderProjectionWritesFailing.md](OrderProjectionWritesFailing.md) |

`OrderCancellationOutboxFailed` and `OrderCompleteFailures` have no runbook file
yet — both are covered by the alert's own annotations and by the sibling
stalled/projection runbooks. Noted here rather than linked, so the index stays
true.

### RFC-0021 phase 6 (payment doubt)

Rules: [`prometheusrules/microservices/rfc0021-phase6.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase6.yaml) ·
catalog: [§9b RFC-0021 phase 6](../../alerting/alert-catalog.md#9b-rfc-0021-phase-6-payment-doubt)

Payment can now record that it does **not know** what the provider did. These
alerts are what make that state safe rather than a place payments disappear
into: they watch how much doubt exists, how old the oldest is, and whether the
automatic resolution paths are working.

| Alert | Sev | Category | Runbook |
|-------|-----|----------|---------|
| PaymentDoubtStale | critical | correctness | [PaymentDoubtStale.md](PaymentDoubtStale.md) |
| PaymentAttemptEvidenceLost | critical | correctness | [PaymentAttemptEvidenceLost.md](PaymentAttemptEvidenceLost.md) |
| PaymentReconciliationDiscrepancy | critical | correctness | [PaymentReconciliationDiscrepancy.md](PaymentReconciliationDiscrepancy.md) |
| PaymentReconciliationStale | critical | observability | [PaymentReconciliationStale.md](PaymentReconciliationStale.md) |
| PaymentDoubtBacklogGrowing | warning | correctness | [PaymentDoubtBacklogGrowing.md](PaymentDoubtBacklogGrowing.md) |
| PaymentDoubtSweepFailing | warning | availability | [PaymentDoubtSweepFailing.md](PaymentDoubtSweepFailing.md) |
| PaymentProviderUnknownRate | warning | availability | [PaymentProviderUnknownRate.md](PaymentProviderUnknownRate.md) |

## Retired alerts (reference only)

Documented in [`../microservices-alerts.md`](../microservices-alerts.md): in-flight
saturation (`MicroserviceHighRequestsInFlight`), `MicroserviceGCThrash`,
`MicroserviceHighRestartRate` (use `KubePodCrashLooping`).

---
_Last updated: 2026-08-02_
