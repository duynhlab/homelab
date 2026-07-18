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

## Retired alerts (reference only)

Documented in [`../microservices-alerts.md`](../microservices-alerts.md): in-flight
saturation (`MicroserviceHighRequestsInFlight`), `MicroserviceGCThrash`,
`MicroserviceHighRestartRate` (use `KubePodCrashLooping`).

---
_Last updated: 2026-07-18_
