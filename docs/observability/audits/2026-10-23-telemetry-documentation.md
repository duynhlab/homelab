# Telemetry documentation review

**Date:** 2026-10-23. **Scope:** application telemetry contracts, the observability
area, and related Compose/Kind verification entry points. This record separates
editorial/source review from runtime evidence. No cluster or release gate was
run as part of the documentation work.

## Ownership and reader model

| Document family | Reader's question | Owns | Evidence source |
|---|---|---|---|
| API contract and pillars | What must my service do? | Normative instrumentation behavior | Shared modules, service code, accepted design records |
| Implementation guide | How do I wire and test it? | Task sequence and excerpts; links to rules | Consumed Go APIs and behavioral audit |
| Fundamentals | How do signals and context fit together? | Concepts, then current request example, then history | Current topology plus labelled design history |
| Platform/backend guides | Where does data go and how is it operated? | Deployment, routing and operational constraints | Active manifests and pinned artifacts |
| Runbooks | What do I inspect, restore and verify? | Alert-specific procedure | Rule expression, component config, dated runtime evidence if available |
| Audits and archived references | What was observed at that revision? | Historical evidence | Recorded revision/date/environment; not current compliance |

The implementation guide is non-normative. Existing signal schemas, env tables,
privacy rules and release requirements keep their current owners. No finding
from the code audit was closed merely because its documentation was clarified.

## Evidence and remaining work

- The dashboard reference was rebuilt from OCI `v0.7.0`, source
  `fb6ebf8e72c740f2aa0913e4f60dd2e4ce4c92fb`, digest
  `sha256:2a97ec2e797f23fb8d2c00719244df0aea81c3a33a987df18b9cedcdabe6f2e7`.
  It has 41 panel elements and seven rows. The Compose twin was not certified.
- `OtelMetricsPipelineExportFailures`' manifest annotation still says five
  minutes and points/second despite a 15-minute increase and `for: 0m`.
  Correct that annotation in a manifest change; the runbook now states the
  actual expression. This docs change deliberately does not edit manifests.
- Existing broad runbook catalogs have uneven validation/recovery metadata.
  The inventory below exposes structural gaps; it is not a claim that every
  infrastructure incident procedure was semantically revalidated. Collector,
  export failure, Pyroscope and vmagent queue-loss procedures received focused
  content review. Domain-specific fault drills remain the Linux operator's work.
- Historical audit dates and migration evidence remain unchanged. Old panel
  material is retained in the labelled historical reference, outside the
  current dashboard lookup path.

## Verification of this documentation change

Checked on 2026-10-23 in the homelab worktree:

| Check | Result | Scope / limit |
|---|---|---|
| `make validate` | Pass | Repository validation, not runtime config acceptance |
| `git diff --check` | Pass | Changed files |
| Relative links, local heading anchors and fences | Pass in changed/new docs | Historical CHANGELOG links/fences remain untouched; released content compared byte-for-byte |
| Mermaid render | 97/97 pass | All diagrams in observability plus the reviewed API guides; changed topology/request images visually inspected |
| Go excerpt compilation | Pass | Bootstrap, middleware, manual span and shutdown excerpts compiled together in a disposable user-service copy against consumed dependencies; no runtime assertion |
| Dashboard artifact inspection | Pass | OCI digest and generated V2 layout checked; no live Grafana queries |
| Linux Kind / Compose | Not run | Checklist is a handoff, not evidence that the environment passed |

## Publication checks on 2026-10-26

The documentation branch was rebased onto main `a75bf42e957026c575630f0bd391b94245453998`.
The 2026-10-23 audit evidence above is unchanged. Main now pins dashboard artifact
`v0.8.0`; its extracted spec adds pool connection-failure and eviction panels
(43 elements, seven rows). The current dashboard reference was updated from
that artifact, with its digest, without claiming live query validation.

On macOS, the new main validator invokes `paste -sd ' '` without a file, which
BSD paste rejects. Validation is rerun with a temporary wrapper supplying `-`
for that exact invocation; repository scripts are unchanged. Linux CI runs the
repository's unmodified command. This is an environment workaround, not a
runtime telemetry check.

## Per-document review inventory

This is a structural inventory, not a compliance score. “Focused edit” denotes
source-backed editorial review in this change; “structure only” means links,
fences/headings and diagrams were checked, not every command's runtime behavior.
The reader/owner column follows the family table above. Missing runbook sections
are follow-up review candidates, not a request to add empty boilerplate.

| Document | Reader / owner | Review depth | Structural follow-up |
|---|---|---|---|
| [docs/observability/README.md](../README.md) | Platform/backend | Focused edit | — |
| [docs/observability/alerting/README.md](../alerting/README.md) | Platform/backend | Structure only | — |
| [docs/observability/alerting/alert-catalog.md](../alerting/alert-catalog.md) | Platform/backend | Structure only | — |
| [docs/observability/alerting/alert-lifecycle-and-runbooks.md](../alerting/alert-lifecycle-and-runbooks.md) | Platform/backend | Structure only | — |
| [docs/observability/alerting/dashboard-comparison.md](../alerting/dashboard-comparison.md) | Platform/backend | Structure only | — |
| [docs/observability/alerting/slo-burn-rate-alerts.md](../alerting/slo-burn-rate-alerts.md) | Platform/backend | Structure only | — |
| [docs/observability/audits/2026-09-16-telemetry-standards.md](2026-09-16-telemetry-standards.md) | Historical evidence/reference | Structure only | — |
| [docs/observability/audits/2026-10-23-telemetry-implementation.md](2026-10-23-telemetry-implementation.md) | Historical evidence/reference | Structure only | — |
| [docs/observability/clickhouse/README.md](../clickhouse/README.md) | Platform/backend | Focused edit | — |
| [docs/observability/clickhouse/audits/2026-09-10-kind.md](../clickhouse/audits/2026-09-10-kind.md) | Historical evidence/reference | Structure only | — |
| [docs/observability/clickhouse/audits/README.md](../clickhouse/audits/README.md) | Historical evidence/reference | Structure only | — |
| [docs/observability/clickhouse/fundamentals.md](../clickhouse/fundamentals.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/01-architecture.md](../clickhouse/internals/01-architecture.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/02-query-pipeline.md](../clickhouse/internals/02-query-pipeline.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/03-mergetree.md](../clickhouse/internals/03-mergetree.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/04-parts-and-merges.md](../clickhouse/internals/04-parts-and-merges.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/05-replication.md](../clickhouse/internals/05-replication.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/06-keeper.md](../clickhouse/internals/06-keeper.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/07-sharding.md](../clickhouse/internals/07-sharding.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/08-ingestion-pipeline.md](../clickhouse/internals/08-ingestion-pipeline.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/09-materialized-views.md](../clickhouse/internals/09-materialized-views.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/10-storage-s3.md](../clickhouse/internals/10-storage-s3.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/11-failure-recovery.md](../clickhouse/internals/11-failure-recovery.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/12-scaling.md](../clickhouse/internals/12-scaling.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/README.md](../clickhouse/internals/README.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/internals/_template.md](../clickhouse/internals/_template.md) | Learner / concepts | Structure only | — |
| [docs/observability/clickhouse/materialized-views.md](../clickhouse/materialized-views.md) | Platform/backend | Structure only | — |
| [docs/observability/clickhouse/operations.md](../clickhouse/operations.md) | Platform/backend | Structure only | — |
| [docs/observability/clickhouse/parts-merges-and-ttl.md](../clickhouse/parts-merges-and-ttl.md) | Platform/backend | Structure only | — |
| [docs/observability/clickhouse/schema-and-queries.md](../clickhouse/schema-and-queries.md) | Platform/backend | Structure only | — |
| [docs/observability/grafana/README.md](../grafana/README.md) | Platform/backend | Focused edit | — |
| [docs/observability/grafana/dashboard-reference-legacy.md](../grafana/dashboard-reference-legacy.md) | Historical evidence/reference | Structure only | — |
| [docs/observability/grafana/dashboard-reference.md](../grafana/dashboard-reference.md) | Platform/backend | Focused edit | — |
| [docs/observability/grafana/dashboards-v2.md](../grafana/dashboards-v2.md) | Platform/backend | Structure only | — |
| [docs/observability/grafana/datasources.md](../grafana/datasources.md) | Platform/backend | Structure only | — |
| [docs/observability/grafana/rbac-multi-team.md](../grafana/rbac-multi-team.md) | Platform/backend | Structure only | — |
| [docs/observability/grafana/variables.md](../grafana/variables.md) | Platform/backend | Structure only | — |
| [docs/observability/logging/README.md](../logging/README.md) | Platform/backend | Structure only | — |
| [docs/observability/logging/logsql-guide.md](../logging/logsql-guide.md) | Platform/backend | Structure only | — |
| [docs/observability/logging/vector.md](../logging/vector.md) | Platform/backend | Structure only | — |
| [docs/observability/logging/victorialogs.md](../logging/victorialogs.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/README.md](../metrics/README.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/histograms.md](../metrics/histograms.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/metrics-apps.md](../metrics/metrics-apps.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/metrics-catalog.md](../metrics/metrics-catalog.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/metrics-infra.md](../metrics/metrics-infra.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/postgresql/README.md](../metrics/postgresql/README.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/postgresql/builtin-metrics.md](../metrics/postgresql/builtin-metrics.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/postgresql/custom-metrics.md](../metrics/postgresql/custom-metrics.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/postgresql/query-telemetry.md](../metrics/postgresql/query-telemetry.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/postgresql/signals/capacity-planning.md](../metrics/postgresql/signals/capacity-planning.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/postgresql/signals/index-hygiene.md](../metrics/postgresql/signals/index-hygiene.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/promql-guide.md](../metrics/promql-guide.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/streaming-aggregation.md](../metrics/streaming-aggregation.md) | Platform/backend | Structure only | — |
| [docs/observability/metrics/victoriametrics.md](../metrics/victoriametrics.md) | Platform/backend | Structure only | — |
| [docs/observability/opentelemetry/README.md](../opentelemetry/README.md) | Platform/backend | Focused edit | — |
| [docs/observability/opentelemetry/collector.md](../opentelemetry/collector.md) | Platform/backend | Focused edit | — |
| [docs/observability/opentelemetry/fundamentals.md](../opentelemetry/fundamentals.md) | Learner / concepts | Focused edit | — |
| [docs/observability/profiling/README.md](../profiling/README.md) | Platform/backend | Focused edit | — |
| [docs/observability/runbooks/README.md](../runbooks/README.md) | Operator / verification | Focused edit | — |
| [docs/observability/runbooks/_TEMPLATE.md](../runbooks/_TEMPLATE.md) | Operator / verification | Structure only | — |
| [docs/observability/runbooks/clickhouse/ClickHouseAllReplicasUnreachable.md](../runbooks/clickhouse/ClickHouseAllReplicasUnreachable.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseDiskAlmostFull.md](../runbooks/clickhouse/ClickHouseDiskAlmostFull.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseDiskCritical.md](../runbooks/clickhouse/ClickHouseDiskCritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseExporterUnhealthy.md](../runbooks/clickhouse/ClickHouseExporterUnhealthy.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseInsertsDelayed.md](../runbooks/clickhouse/ClickHouseInsertsDelayed.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseInsertsFailing.md](../runbooks/clickhouse/ClickHouseInsertsFailing.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseInsertsRejected.md](../runbooks/clickhouse/ClickHouseInsertsRejected.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseKeeperNoLeader.md](../runbooks/clickhouse/ClickHouseKeeperNoLeader.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseKeeperQuorumDegraded.md](../runbooks/clickhouse/ClickHouseKeeperQuorumDegraded.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseKeeperSessionLost.md](../runbooks/clickhouse/ClickHouseKeeperSessionLost.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseOperatorDown.md](../runbooks/clickhouse/ClickHouseOperatorDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseOperatorReconcileErrors.md](../runbooks/clickhouse/ClickHouseOperatorReconcileErrors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseOtelTTLLagging.md](../runbooks/clickhouse/ClickHouseOtelTTLLagging.md) | Operator / verification | Structure only | Review sections: Impact |
| [docs/observability/runbooks/clickhouse/ClickHouseReadonlyReplica.md](../runbooks/clickhouse/ClickHouseReadonlyReplica.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseReplicaUnreachable.md](../runbooks/clickhouse/ClickHouseReplicaUnreachable.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseReplicatedDataLoss.md](../runbooks/clickhouse/ClickHouseReplicatedDataLoss.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseReplicationLag.md](../runbooks/clickhouse/ClickHouseReplicationLag.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseS3Errors.md](../runbooks/clickhouse/ClickHouseS3Errors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseServerErrorsElevated.md](../runbooks/clickhouse/ClickHouseServerErrorsElevated.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseServerNotScraped.md](../runbooks/clickhouse/ClickHouseServerNotScraped.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseTooManyParts.md](../runbooks/clickhouse/ClickHouseTooManyParts.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseTooManyPartsPerPartition.md](../runbooks/clickhouse/ClickHouseTooManyPartsPerPartition.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/ClickHouseZooKeeperExceptions.md](../runbooks/clickhouse/ClickHouseZooKeeperExceptions.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/clickhouse/README.md](../runbooks/clickhouse/README.md) | Operator / verification | Structure only | — |
| [docs/observability/runbooks/envoy-gateway/Edge429RatioHigh.md](../runbooks/envoy-gateway/Edge429RatioHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/Edge5xxRatio.md](../runbooks/envoy-gateway/Edge5xxRatio.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/EdgeAuthDeniedRatioHigh.md](../runbooks/envoy-gateway/EdgeAuthDeniedRatioHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/EdgeCertExpiry.md](../runbooks/envoy-gateway/EdgeCertExpiry.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/EdgeDown.md](../runbooks/envoy-gateway/EdgeDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/EdgeJWKSFetchFailing.md](../runbooks/envoy-gateway/EdgeJWKSFetchFailing.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/EdgeLatencyP95.md](../runbooks/envoy-gateway/EdgeLatencyP95.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/EdgeNoTraffic.md](../runbooks/envoy-gateway/EdgeNoTraffic.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/EdgeUpstreamNoHealthyEndpoints.md](../runbooks/envoy-gateway/EdgeUpstreamNoHealthyEndpoints.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/EdgeUpstreamTimeoutRatioHigh.md](../runbooks/envoy-gateway/EdgeUpstreamTimeoutRatioHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/EdgeUpstreamUnhealthy.md](../runbooks/envoy-gateway/EdgeUpstreamUnhealthy.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/EnvoyGatewayControllerDown.md](../runbooks/envoy-gateway/EnvoyGatewayControllerDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/EnvoyGatewayReconcileErrors.md](../runbooks/envoy-gateway/EnvoyGatewayReconcileErrors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/envoy-gateway/README.md](../runbooks/envoy-gateway/README.md) | Operator / verification | Structure only | — |
| [docs/observability/runbooks/gitops/CertManagerCertExpiringSoon.md](../runbooks/gitops/CertManagerCertExpiringSoon.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/gitops/CertManagerCertExpiryCritical.md](../runbooks/gitops/CertManagerCertExpiryCritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/gitops/CertManagerCertNotReady.md](../runbooks/gitops/CertManagerCertNotReady.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/gitops/FluxHelmReleaseNotReady.md](../runbooks/gitops/FluxHelmReleaseNotReady.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/gitops/FluxKustomizationNotReady.md](../runbooks/gitops/FluxKustomizationNotReady.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/gitops/FluxReconcileDurationHigh.md](../runbooks/gitops/FluxReconcileDurationHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/gitops/FluxReconciliationFailure.md](../runbooks/gitops/FluxReconciliationFailure.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/gitops/FluxSourceNotReady.md](../runbooks/gitops/FluxSourceNotReady.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/gitops/FluxSuspendedResource.md](../runbooks/gitops/FluxSuspendedResource.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/keda/KedaMetricsApiServerDown.md](../runbooks/keda/KedaMetricsApiServerDown.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/keda/KedaOperatorDown.md](../runbooks/keda/KedaOperatorDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/keda/KedaScaledObjectErrors.md](../runbooks/keda/KedaScaledObjectErrors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/keda/KedaScalerErrors.md](../runbooks/keda/KedaScalerErrors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/keda/README.md](../runbooks/keda/README.md) | Operator / verification | Structure only | — |
| [docs/observability/runbooks/keycloak/KeycloakDbPoolExhausted.md](../runbooks/keycloak/KeycloakDbPoolExhausted.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/keycloak/KeycloakDown.md](../runbooks/keycloak/KeycloakDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/keycloak/KeycloakLoginFailureRatioHigh.md](../runbooks/keycloak/KeycloakLoginFailureRatioHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/keycloak/KeycloakRestartLoop.md](../runbooks/keycloak/KeycloakRestartLoop.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/keycloak/KeycloakTokenLatencyHigh.md](../runbooks/keycloak/KeycloakTokenLatencyHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/CoreDNSDown.md](../runbooks/kubernetes/CoreDNSDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/CoreDNSHighErrorRate.md](../runbooks/kubernetes/CoreDNSHighErrorRate.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/EtcdHighCommitDurations.md](../runbooks/kubernetes/EtcdHighCommitDurations.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/EtcdHighFsyncDurations.md](../runbooks/kubernetes/EtcdHighFsyncDurations.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/EtcdHighNumberOfLeaderChanges.md](../runbooks/kubernetes/EtcdHighNumberOfLeaderChanges.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/EtcdMembersDown.md](../runbooks/kubernetes/EtcdMembersDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeAPIServerDown.md](../runbooks/kubernetes/KubeAPIServerDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeAPIServerErrorRate.md](../runbooks/kubernetes/KubeAPIServerErrorRate.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeAPIServerHighInflight.md](../runbooks/kubernetes/KubeAPIServerHighInflight.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeAPIServerHighLatency.md](../runbooks/kubernetes/KubeAPIServerHighLatency.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeContainerNetworkErrors.md](../runbooks/kubernetes/KubeContainerNetworkErrors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeDeploymentReplicasMismatch.md](../runbooks/kubernetes/KubeDeploymentReplicasMismatch.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeHPAMaxedOut.md](../runbooks/kubernetes/KubeHPAMaxedOut.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeJobFailed.md](../runbooks/kubernetes/KubeJobFailed.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeNodeDiskPressure.md](../runbooks/kubernetes/KubeNodeDiskPressure.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeNodeMemoryPressure.md](../runbooks/kubernetes/KubeNodeMemoryPressure.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeNodeNotReady.md](../runbooks/kubernetes/KubeNodeNotReady.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeNodePIDPressure.md](../runbooks/kubernetes/KubeNodePIDPressure.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeNodeUnschedulable.md](../runbooks/kubernetes/KubeNodeUnschedulable.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubePersistentVolumeFillingUp.md](../runbooks/kubernetes/KubePersistentVolumeFillingUp.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubePersistentVolumeFillingUpCritical.md](../runbooks/kubernetes/KubePersistentVolumeFillingUpCritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubePodCPUThrottlingHigh.md](../runbooks/kubernetes/KubePodCPUThrottlingHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubePodCrashLooping.md](../runbooks/kubernetes/KubePodCrashLooping.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubePodMemoryNearLimit.md](../runbooks/kubernetes/KubePodMemoryNearLimit.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubePodNotReady.md](../runbooks/kubernetes/KubePodNotReady.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubePodOOMKilled.md](../runbooks/kubernetes/KubePodOOMKilled.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeStatefulSetReplicasMismatch.md](../runbooks/kubernetes/KubeStatefulSetReplicasMismatch.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeletDown.md](../runbooks/kubernetes/KubeletDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/KubeletTooManyPods.md](../runbooks/kubernetes/KubeletTooManyPods.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kubernetes/README.md](../runbooks/kubernetes/README.md) | Operator / verification | Structure only | — |
| [docs/observability/runbooks/kyverno/KyvernoAdmissionDenying.md](../runbooks/kyverno/KyvernoAdmissionDenying.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kyverno/KyvernoAdmissionLatencyHigh.md](../runbooks/kyverno/KyvernoAdmissionLatencyHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kyverno/KyvernoControllerDown.md](../runbooks/kyverno/KyvernoControllerDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kyverno/KyvernoPolicyRuleErrors.md](../runbooks/kyverno/KyvernoPolicyRuleErrors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/kyverno/README.md](../runbooks/kyverno/README.md) | Operator / verification | Structure only | — |
| [docs/observability/runbooks/microservices/CheckoutAvailabilityErrors.md](../runbooks/microservices/CheckoutAvailabilityErrors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/CheckoutAvailabilityRefusingEverything.md](../runbooks/microservices/CheckoutAvailabilityRefusingEverything.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/CheckoutAvailabilityUnknownSKU.md](../runbooks/microservices/CheckoutAvailabilityUnknownSKU.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/DBClientErrorRate.md](../runbooks/microservices/DBClientErrorRate.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/DBClientQueryP95High.md](../runbooks/microservices/DBClientQueryP95High.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/microservices/FulfillmentStartOutboxFailed.md](../runbooks/microservices/FulfillmentStartOutboxFailed.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/FulfillmentStartOutboxStalled.md](../runbooks/microservices/FulfillmentStartOutboxStalled.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/GrpcServerHighErrorRate.md](../runbooks/microservices/GrpcServerHighErrorRate.md) | Operator / verification | Structure only | Review sections: Impact, Escalation |
| [docs/observability/runbooks/microservices/GrpcServerHighLatencyP95.md](../runbooks/microservices/GrpcServerHighLatencyP95.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/InventoryGrpcErrorRatio.md](../runbooks/microservices/InventoryGrpcErrorRatio.md) | Operator / verification | Structure only | Review sections: Meaning, Impact, Escalation |
| [docs/observability/runbooks/microservices/InventoryReservationInfraErrors.md](../runbooks/microservices/InventoryReservationInfraErrors.md) | Operator / verification | Structure only | Review sections: Meaning, Impact, Escalation |
| [docs/observability/runbooks/microservices/InventoryReserveUnknownSKU.md](../runbooks/microservices/InventoryReserveUnknownSKU.md) | Operator / verification | Structure only | Review sections: Meaning, Impact, Escalation |
| [docs/observability/runbooks/microservices/KubeStateMetricsAbsent.md](../runbooks/microservices/KubeStateMetricsAbsent.md) | Operator / verification | Structure only | Review sections: Escalation |
| [docs/observability/runbooks/microservices/MicroserviceAllInstancesDown.md](../runbooks/microservices/MicroserviceAllInstancesDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/MicroserviceApdexCritical.md](../runbooks/microservices/MicroserviceApdexCritical.md) | Operator / verification | Structure only | Review sections: Diagnosis, Mitigation, Escalation |
| [docs/observability/runbooks/microservices/MicroserviceDown.md](../runbooks/microservices/MicroserviceDown.md) | Operator / verification | Structure only | Review sections: Escalation |
| [docs/observability/runbooks/microservices/MicroserviceErrorRateCritical.md](../runbooks/microservices/MicroserviceErrorRateCritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/MicroserviceGoroutineLeak.md](../runbooks/microservices/MicroserviceGoroutineLeak.md) | Operator / verification | Structure only | Review sections: Escalation |
| [docs/observability/runbooks/microservices/MicroserviceHighErrorRate.md](../runbooks/microservices/MicroserviceHighErrorRate.md) | Operator / verification | Structure only | Review sections: Escalation |
| [docs/observability/runbooks/microservices/MicroserviceHighLatencyP95.md](../runbooks/microservices/MicroserviceHighLatencyP95.md) | Operator / verification | Structure only | Review sections: Escalation |
| [docs/observability/runbooks/microservices/MicroserviceHighLatencyP99.md](../runbooks/microservices/MicroserviceHighLatencyP99.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/MicroserviceHighMemoryUsage.md](../runbooks/microservices/MicroserviceHighMemoryUsage.md) | Operator / verification | Structure only | Review sections: Escalation |
| [docs/observability/runbooks/microservices/MicroserviceLatencyCritical.md](../runbooks/microservices/MicroserviceLatencyCritical.md) | Operator / verification | Structure only | Review sections: Diagnosis, Mitigation, Escalation |
| [docs/observability/runbooks/microservices/MicroserviceNoSuccessfulRequests.md](../runbooks/microservices/MicroserviceNoSuccessfulRequests.md) | Operator / verification | Structure only | Review sections: Escalation |
| [docs/observability/runbooks/microservices/MicroserviceNoTraffic.md](../runbooks/microservices/MicroserviceNoTraffic.md) | Operator / verification | Structure only | Review sections: Escalation |
| [docs/observability/runbooks/microservices/OrderCancellationOutboxStalled.md](../runbooks/microservices/OrderCancellationOutboxStalled.md) | Operator / verification | Structure only | Review sections: Impact, Mitigation, Escalation |
| [docs/observability/runbooks/microservices/OrderInventoryCommitLagHigh.md](../runbooks/microservices/OrderInventoryCommitLagHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/OrderManualReviewBacklog.md](../runbooks/microservices/OrderManualReviewBacklog.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/microservices/OrderParticipantDisagreement.md](../runbooks/microservices/OrderParticipantDisagreement.md) | Operator / verification | Structure only | Review sections: Escalation |
| [docs/observability/runbooks/microservices/OrderProjectionWritesFailing.md](../runbooks/microservices/OrderProjectionWritesFailing.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/microservices/OrderReconcilerBacklogNotDraining.md](../runbooks/microservices/OrderReconcilerBacklogNotDraining.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/OrderReconcilerBacklogUnreadable.md](../runbooks/microservices/OrderReconcilerBacklogUnreadable.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/OrderReconcilerDependencyUnreadable.md](../runbooks/microservices/OrderReconcilerDependencyUnreadable.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/OrderReconcilerInvariantBreach.md](../runbooks/microservices/OrderReconcilerInvariantBreach.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/OrderReconcilerPassTruncated.md](../runbooks/microservices/OrderReconcilerPassTruncated.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/OrderSagaCompensationFailing.md](../runbooks/microservices/OrderSagaCompensationFailing.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/OrderSagaNotCompleting.md](../runbooks/microservices/OrderSagaNotCompleting.md) | Operator / verification | Structure only | Review sections: Escalation |
| [docs/observability/runbooks/microservices/OrderStartParticipantUnrecognised.md](../runbooks/microservices/OrderStartParticipantUnrecognised.md) | Operator / verification | Structure only | Review sections: Escalation |
| [docs/observability/runbooks/microservices/OrderStuckCancelling.md](../runbooks/microservices/OrderStuckCancelling.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/microservices/OtelMetricsPipelineExportFailures.md](../runbooks/microservices/OtelMetricsPipelineExportFailures.md) | Operator / verification | Focused edit | — |
| [docs/observability/runbooks/microservices/PaymentAttemptEvidenceLost.md](../runbooks/microservices/PaymentAttemptEvidenceLost.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/microservices/PaymentDoubtBacklogGrowing.md](../runbooks/microservices/PaymentDoubtBacklogGrowing.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/microservices/PaymentDoubtStale.md](../runbooks/microservices/PaymentDoubtStale.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/microservices/PaymentDoubtSweepFailing.md](../runbooks/microservices/PaymentDoubtSweepFailing.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/microservices/PaymentProviderUnknownRate.md](../runbooks/microservices/PaymentProviderUnknownRate.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/microservices/PaymentReconciliationDiscrepancy.md](../runbooks/microservices/PaymentReconciliationDiscrepancy.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/microservices/PaymentReconciliationStale.md](../runbooks/microservices/PaymentReconciliationStale.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/microservices/PaymentReconciliationWindowViolation.md](../runbooks/microservices/PaymentReconciliationWindowViolation.md) | Operator / verification | Structure only | Review sections: Meaning, Impact, Escalation |
| [docs/observability/runbooks/microservices/PgxPoolAcquireWaitHigh.md](../runbooks/microservices/PgxPoolAcquireWaitHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/microservices/PgxPoolNearExhaustion.md](../runbooks/microservices/PgxPoolNearExhaustion.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/microservices/README.md](../runbooks/microservices/README.md) | Operator / verification | Structure only | — |
| [docs/observability/runbooks/observability/OtelCollectorDown.md](../runbooks/observability/OtelCollectorDown.md) | Operator / verification | Focused edit | — |
| [docs/observability/runbooks/observability/PolicyReporterDown.md](../runbooks/observability/PolicyReporterDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/observability/PyroscopeDown.md](../runbooks/observability/PyroscopeDown.md) | Operator / verification | Focused edit | — |
| [docs/observability/runbooks/observability/Watchdog.md](../runbooks/observability/Watchdog.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGAuthorizationGuardMissing.md](../runbooks/postgresql/CNPGAuthorizationGuardMissing.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGAutovacuumFallingBehind.md](../runbooks/postgresql/CNPGAutovacuumFallingBehind.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGBlockedQueries.md](../runbooks/postgresql/CNPGBlockedQueries.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGCheckpointPressure.md](../runbooks/postgresql/CNPGCheckpointPressure.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterHACritical.md](../runbooks/postgresql/CNPGClusterHACritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterHAWarning.md](../runbooks/postgresql/CNPGClusterHAWarning.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterHighConnectionsCritical.md](../runbooks/postgresql/CNPGClusterHighConnectionsCritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterHighConnectionsWarning.md](../runbooks/postgresql/CNPGClusterHighConnectionsWarning.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterHighReplicationLag.md](../runbooks/postgresql/CNPGClusterHighReplicationLag.md) | Operator / verification | Structure only | — |
| [docs/observability/runbooks/postgresql/CNPGClusterInstancesOnSameNode.md](../runbooks/postgresql/CNPGClusterInstancesOnSameNode.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterLogicalReplicationErrors.md](../runbooks/postgresql/CNPGClusterLogicalReplicationErrors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterLogicalReplicationErrorsCritical.md](../runbooks/postgresql/CNPGClusterLogicalReplicationErrorsCritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterLogicalReplicationLagging.md](../runbooks/postgresql/CNPGClusterLogicalReplicationLagging.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterLogicalReplicationLaggingCritical.md](../runbooks/postgresql/CNPGClusterLogicalReplicationLaggingCritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterLogicalReplicationStopped.md](../runbooks/postgresql/CNPGClusterLogicalReplicationStopped.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterLogicalReplicationStoppedCritical.md](../runbooks/postgresql/CNPGClusterLogicalReplicationStoppedCritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterLowDiskSpaceCritical.md](../runbooks/postgresql/CNPGClusterLowDiskSpaceCritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterLowDiskSpaceWarning.md](../runbooks/postgresql/CNPGClusterLowDiskSpaceWarning.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterOffline.md](../runbooks/postgresql/CNPGClusterOffline.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterPhysicalReplicationLagCritical.md](../runbooks/postgresql/CNPGClusterPhysicalReplicationLagCritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterPhysicalReplicationLagWarning.md](../runbooks/postgresql/CNPGClusterPhysicalReplicationLagWarning.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGClusterStandbyNotStreaming.md](../runbooks/postgresql/CNPGClusterStandbyNotStreaming.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/postgresql/CNPGClusterZoneSpreadWarning.md](../runbooks/postgresql/CNPGClusterZoneSpreadWarning.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGControllerReconcileErrorsSpiking.md](../runbooks/postgresql/CNPGControllerReconcileErrorsSpiking.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGDRClusterOffline.md](../runbooks/postgresql/CNPGDRClusterOffline.md) | Operator / verification | Structure only | — |
| [docs/observability/runbooks/postgresql/CNPGDeadlocksIncreasing.md](../runbooks/postgresql/CNPGDeadlocksIncreasing.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGDefaultPrivilegesDrift.md](../runbooks/postgresql/CNPGDefaultPrivilegesDrift.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGIdleInTransaction.md](../runbooks/postgresql/CNPGIdleInTransaction.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGInactiveSlotRetainingWAL.md](../runbooks/postgresql/CNPGInactiveSlotRetainingWAL.md) | Operator / verification | Structure only | Review sections: Mitigation, Escalation |
| [docs/observability/runbooks/postgresql/CNPGLongRunningTransaction.md](../runbooks/postgresql/CNPGLongRunningTransaction.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGLowCacheHitRatio.md](../runbooks/postgresql/CNPGLowCacheHitRatio.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGOperatorDown.md](../runbooks/postgresql/CNPGOperatorDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGRoleConfigDrift.md](../runbooks/postgresql/CNPGRoleConfigDrift.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGRoleMembershipDrift.md](../runbooks/postgresql/CNPGRoleMembershipDrift.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGRoleMembershipGuardMissing.md](../runbooks/postgresql/CNPGRoleMembershipGuardMissing.md) | Operator / verification | Structure only | Review sections: Impact, Escalation |
| [docs/observability/runbooks/postgresql/CNPGTempFileSpill.md](../runbooks/postgresql/CNPGTempFileSpill.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGTransactionIDWraparoundCritical.md](../runbooks/postgresql/CNPGTransactionIDWraparoundCritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGTransactionIDWraparoundWarning.md](../runbooks/postgresql/CNPGTransactionIDWraparoundWarning.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CNPGWALArchiveFailing.md](../runbooks/postgresql/CNPGWALArchiveFailing.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/CnpgClusterFenced.md](../runbooks/postgresql/CnpgClusterFenced.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/PgStatChDroppingEvents.md](../runbooks/postgresql/PgStatChDroppingEvents.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/PgStatChExportFailing.md](../runbooks/postgresql/PgStatChExportFailing.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/PgStatChNotExporting.md](../runbooks/postgresql/PgStatChNotExporting.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/PostgresWALSizeHigh.md](../runbooks/postgresql/PostgresWALSizeHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/postgresql/README.md](../runbooks/postgresql/README.md) | Operator / verification | Structure only | — |
| [docs/observability/runbooks/postgresql/plan-regression-investigation.md](../runbooks/postgresql/plan-regression-investigation.md) | Operator / verification | Structure only | Review sections: Meaning, Impact |
| [docs/observability/runbooks/telemetry-kind-verification.md](../runbooks/telemetry-kind-verification.md) | Operator / verification | Focused edit | — |
| [docs/observability/runbooks/temporal/README.md](../runbooks/temporal/README.md) | Operator / verification | Structure only | — |
| [docs/observability/runbooks/temporal/TemporalActivityFailureRateHigh.md](../runbooks/temporal/TemporalActivityFailureRateHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/temporal/TemporalPersistenceErrorRateHigh.md](../runbooks/temporal/TemporalPersistenceErrorRateHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/temporal/TemporalScheduleToStartLatencyHigh.md](../runbooks/temporal/TemporalScheduleToStartLatencyHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/temporal/TemporalServerDown.md](../runbooks/temporal/TemporalServerDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/temporal/TemporalServiceErrorRateHigh.md](../runbooks/temporal/TemporalServiceErrorRateHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/temporal/TemporalTaskQueueBacklogGrowing.md](../runbooks/temporal/TemporalTaskQueueBacklogGrowing.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/temporal/TemporalWorkerRequestErrorRateHigh.md](../runbooks/temporal/TemporalWorkerRequestErrorRateHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/temporal/TemporalWorkerTaskSlotsExhausted.md](../runbooks/temporal/TemporalWorkerTaskSlotsExhausted.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/temporal/TemporalWorkflowFailureRateHigh.md](../runbooks/temporal/TemporalWorkflowFailureRateHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/valkey/README.md](../runbooks/valkey/README.md) | Operator / verification | Structure only | — |
| [docs/observability/runbooks/valkey/ValkeyDown.md](../runbooks/valkey/ValkeyDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/valkey/ValkeyHighClientConnections.md](../runbooks/valkey/ValkeyHighClientConnections.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/valkey/ValkeyHighEvictionRate.md](../runbooks/valkey/ValkeyHighEvictionRate.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/valkey/ValkeyHighMissRatio.md](../runbooks/valkey/ValkeyHighMissRatio.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/valkey/ValkeyMemorySaturation.md](../runbooks/valkey/ValkeyMemorySaturation.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/valkey/ValkeyMemorySaturationCritical.md](../runbooks/valkey/ValkeyMemorySaturationCritical.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/valkey/ValkeyRejectedConnections.md](../runbooks/valkey/ValkeyRejectedConnections.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAgentConfigurationReloadFailure.md](../runbooks/victoriametrics/VMAgentConfigurationReloadFailure.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAgentPersistentQueueIsDroppingData.md](../runbooks/victoriametrics/VMAgentPersistentQueueIsDroppingData.md) | Operator / verification | Focused edit | — |
| [docs/observability/runbooks/victoriametrics/VMAgentPersistentQueueRunsOutOfSpaceIn12Hours.md](../runbooks/victoriametrics/VMAgentPersistentQueueRunsOutOfSpaceIn12Hours.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAgentPersistentQueueRunsOutOfSpaceIn4Hours.md](../runbooks/victoriametrics/VMAgentPersistentQueueRunsOutOfSpaceIn4Hours.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAgentRemoteWriteConnectionIsSaturated.md](../runbooks/victoriametrics/VMAgentRemoteWriteConnectionIsSaturated.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAgentScrapePoolHasNoTargets.md](../runbooks/victoriametrics/VMAgentScrapePoolHasNoTargets.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAgentTooManyRemoteWriteErrors.md](../runbooks/victoriametrics/VMAgentTooManyRemoteWriteErrors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAgentTooManyScrapeErrors.md](../runbooks/victoriametrics/VMAgentTooManyScrapeErrors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAlertAlertingRulesError.md](../runbooks/victoriametrics/VMAlertAlertingRulesError.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAlertAlertmanagerErrors.md](../runbooks/victoriametrics/VMAlertAlertmanagerErrors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAlertConfigurationReloadFailure.md](../runbooks/victoriametrics/VMAlertConfigurationReloadFailure.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAlertRecordingRulesError.md](../runbooks/victoriametrics/VMAlertRecordingRulesError.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAlertRemoteWriteDroppingData.md](../runbooks/victoriametrics/VMAlertRemoteWriteDroppingData.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAlertRemoteWriteErrors.md](../runbooks/victoriametrics/VMAlertRemoteWriteErrors.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMAlertTooManyMissedIterations.md](../runbooks/victoriametrics/VMAlertTooManyMissedIterations.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMConcurrentInsertsHitTheLimit.md](../runbooks/victoriametrics/VMConcurrentInsertsHitTheLimit.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMProcessNearFDLimits.md](../runbooks/victoriametrics/VMProcessNearFDLimits.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMRowsRejectedOnIngestion.md](../runbooks/victoriametrics/VMRowsRejectedOnIngestion.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMServiceDown.md](../runbooks/victoriametrics/VMServiceDown.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMSingleDiskRunsOutOfSpace.md](../runbooks/victoriametrics/VMSingleDiskRunsOutOfSpace.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMSingleDiskRunsOutOfSpaceIn3Days.md](../runbooks/victoriametrics/VMSingleDiskRunsOutOfSpaceIn3Days.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMSingleMetadataCacheUtilizationIsTooHigh.md](../runbooks/victoriametrics/VMSingleMetadataCacheUtilizationIsTooHigh.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMSingleRequestErrorsToAPI.md](../runbooks/victoriametrics/VMSingleRequestErrorsToAPI.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMSingleTooHighChurnRate.md](../runbooks/victoriametrics/VMSingleTooHighChurnRate.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMSingleTooHighSlowInsertsRate.md](../runbooks/victoriametrics/VMSingleTooHighSlowInsertsRate.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMTooHighCPUUsage.md](../runbooks/victoriametrics/VMTooHighCPUUsage.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMTooHighMemoryUsage.md](../runbooks/victoriametrics/VMTooHighMemoryUsage.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMTooHighQueryLoad.md](../runbooks/victoriametrics/VMTooHighQueryLoad.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMTooManyLogs.md](../runbooks/victoriametrics/VMTooManyLogs.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMTooManyRestarts.md](../runbooks/victoriametrics/VMTooManyRestarts.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/runbooks/victoriametrics/VMTooManyTSIDMisses.md](../runbooks/victoriametrics/VMTooManyTSIDMisses.md) | Operator / verification | Structure only | Recovery is not a separate section; inspect inline evidence |
| [docs/observability/slo/README.md](../slo/README.md) | Platform/backend | Structure only | — |
| [docs/observability/slo/annotation-driven-slo-controller.md](../slo/annotation-driven-slo-controller.md) | Platform/backend | Structure only | — |
| [docs/observability/slo/error_budget_policy.md](../slo/error_budget_policy.md) | Platform/backend | Structure only | — |
| [docs/observability/slo/fundamentals.md](../slo/fundamentals.md) | Learner / concepts | Structure only | — |
| [docs/observability/slo/getting_started.md](../slo/getting_started.md) | Platform/backend | Structure only | — |
| [docs/observability/tracing/README.md](../tracing/README.md) | Platform/backend | Structure only | — |
| [docs/observability/tracing/architecture.md](../tracing/architecture.md) | Platform/backend | Structure only | — |
| [docs/observability/tracing/backends-comparison.md](../tracing/backends-comparison.md) | Platform/backend | Structure only | — |
| [docs/observability/tracing/jaeger.md](../tracing/jaeger.md) | Platform/backend | Structure only | — |
| [docs/observability/tracing/service-graph.md](../tracing/service-graph.md) | Platform/backend | Structure only | — |
| [docs/observability/tracing/tempo.md](../tracing/tempo.md) | Platform/backend | Structure only | — |
| [docs/observability/tracing/victoriatraces.md](../tracing/victoriatraces.md) | Platform/backend | Structure only | — |
| [docs/api/README.md](../../api/README.md) | Service contract | Focused edit | — |
| [docs/api/observability.md](../../api/observability.md) | Service contract | Focused edit | — |
| [docs/api/logs.md](../../api/logs.md) | Service contract | Structure only | — |
| [docs/api/metrics.md](../../api/metrics.md) | Service contract | Structure only | — |
| [docs/api/tracing.md](../../api/tracing.md) | Service contract | Focused edit | — |
| [docs/api/profiling.md](../../api/profiling.md) | Service contract | Structure only | — |
| [docs/api/graceful-shutdown.md](../../api/graceful-shutdown.md) | Service contract | Structure only | — |
| [docs/api/telemetry-implementation.md](../../api/telemetry-implementation.md) | Service author guide | Focused edit | — |
| [docs/platform/kind-e2e-audit.md](../../platform/kind-e2e-audit.md) | Operator / verification | Structure only | — |
| [local-stack/docs/e2e-audit.md](../../../local-stack/docs/e2e-audit.md) | Operator / verification | Structure only | — |
