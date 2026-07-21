# PostgreSQL Alert Runbooks

Per-alert investigation guides for CloudNativePG chart rules, homelab deep-signal
alerts, and operator health. One file per alert name — each file covers both
`platform-db` (ns `platform`) and `product-db` (ns `product`) unless noted.

| Quick facts | |
|---|---|
| Alert rules | [`prometheusrules/postgres/`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/) |
| Alert catalog | [§4 / §4b](../../alerting/alert-catalog.md#4-postgresql--cloudnativepg) |
| Metrics reference | [postgresql/custom-metrics.md](../../metrics/postgresql/custom-metrics.md) |
| Emergency triage | [010.4-emergency-recovery.md](../../../databases/010.4-emergency-recovery.md) |
| Pooler ops | [pgdog-operations.md](../../../databases/runbooks/pgdog-operations.md) |

## Index

| Alert | Sev | Source | Status | Runbook |
|-------|-----|--------|--------|---------|
| CNPGClusterOffline | critical | chart | active | [CNPGClusterOffline.md](CNPGClusterOffline.md) |
| CnpgClusterFenced | critical | homelab-extra | active | [CnpgClusterFenced.md](CnpgClusterFenced.md) |
| CNPGClusterHACritical | critical | chart | active | [CNPGClusterHACritical.md](CNPGClusterHACritical.md) |
| CNPGClusterHAWarning | warning | chart | active | [CNPGClusterHAWarning.md](CNPGClusterHAWarning.md) |
| CNPGOperatorDown | critical | operator-health | active | [CNPGOperatorDown.md](CNPGOperatorDown.md) |
| CNPGControllerReconcileErrorsSpiking | warning | operator-health | active | [CNPGControllerReconcileErrorsSpiking.md](CNPGControllerReconcileErrorsSpiking.md) |
| CNPGClusterHighConnectionsCritical | critical | chart | active | [CNPGClusterHighConnectionsCritical.md](CNPGClusterHighConnectionsCritical.md) |
| CNPGClusterHighConnectionsWarning | warning | chart | active | [CNPGClusterHighConnectionsWarning.md](CNPGClusterHighConnectionsWarning.md) |
| CNPGClusterPhysicalReplicationLagCritical | critical | chart | active | [CNPGClusterPhysicalReplicationLagCritical.md](CNPGClusterPhysicalReplicationLagCritical.md) |
| CNPGClusterPhysicalReplicationLagWarning | warning | chart | active | [CNPGClusterPhysicalReplicationLagWarning.md](CNPGClusterPhysicalReplicationLagWarning.md) |
| CNPGClusterHighReplicationLag | warning | chart | active | [CNPGClusterHighReplicationLag.md](CNPGClusterHighReplicationLag.md) |
| CNPGClusterLowDiskSpaceCritical | critical | chart | inactive on Kind | [CNPGClusterLowDiskSpaceCritical.md](CNPGClusterLowDiskSpaceCritical.md) |
| CNPGClusterLowDiskSpaceWarning | warning | chart | inactive on Kind | [CNPGClusterLowDiskSpaceWarning.md](CNPGClusterLowDiskSpaceWarning.md) |
| PostgresWALSizeHigh | warning | homelab-extra | active | [PostgresWALSizeHigh.md](PostgresWALSizeHigh.md) |
| CNPGClusterZoneSpreadWarning | warning | chart | gated | [CNPGClusterZoneSpreadWarning.md](CNPGClusterZoneSpreadWarning.md) |
| CNPGClusterInstancesOnSameNode | warning | chart | gated | [CNPGClusterInstancesOnSameNode.md](CNPGClusterInstancesOnSameNode.md) |
| PostgresBackupTooOld | warning | backup-alerts | active | [postgres-backup-restore.md](../../../databases/runbooks/postgres-backup-restore.md) |
| PostgresBackupFailed | critical | backup-alerts | active | [postgres-backup-restore.md](../../../databases/runbooks/postgres-backup-restore.md) |
| CNPGClusterLogicalReplicationErrors | warning | chart | inactive | [CNPGClusterLogicalReplicationErrors.md](CNPGClusterLogicalReplicationErrors.md) |
| CNPGClusterLogicalReplicationErrorsCritical | critical | chart | inactive | [CNPGClusterLogicalReplicationErrorsCritical.md](CNPGClusterLogicalReplicationErrorsCritical.md) |
| CNPGClusterLogicalReplicationLagging | warning | chart | inactive | [CNPGClusterLogicalReplicationLagging.md](CNPGClusterLogicalReplicationLagging.md) |
| CNPGClusterLogicalReplicationLaggingCritical | critical | chart | inactive | [CNPGClusterLogicalReplicationLaggingCritical.md](CNPGClusterLogicalReplicationLaggingCritical.md) |
| CNPGClusterLogicalReplicationStopped | warning | chart | inactive | [CNPGClusterLogicalReplicationStopped.md](CNPGClusterLogicalReplicationStopped.md) |
| CNPGClusterLogicalReplicationStoppedCritical | critical | chart | inactive | [CNPGClusterLogicalReplicationStoppedCritical.md](CNPGClusterLogicalReplicationStoppedCritical.md) |
| CNPGBlockedQueries | warning | deep-signal | active | [CNPGBlockedQueries.md](CNPGBlockedQueries.md) |
| CNPGDeadlocksIncreasing | warning | deep-signal | active | [CNPGDeadlocksIncreasing.md](CNPGDeadlocksIncreasing.md) |
| CNPGAutovacuumFallingBehind | warning | deep-signal | active | [CNPGAutovacuumFallingBehind.md](CNPGAutovacuumFallingBehind.md) |
| CNPGLowCacheHitRatio | warning | deep-signal | active | [CNPGLowCacheHitRatio.md](CNPGLowCacheHitRatio.md) |
| CNPGTempFileSpill | warning | deep-signal | active | [CNPGTempFileSpill.md](CNPGTempFileSpill.md) |
| CNPGCheckpointPressure | warning | deep-signal | active | [CNPGCheckpointPressure.md](CNPGCheckpointPressure.md) |
| CNPGTransactionIDWraparoundWarning | warning | deep-signal | active | [CNPGTransactionIDWraparoundWarning.md](CNPGTransactionIDWraparoundWarning.md) |
| CNPGTransactionIDWraparoundCritical | critical | deep-signal | active | [CNPGTransactionIDWraparoundCritical.md](CNPGTransactionIDWraparoundCritical.md) |
| CNPGWALArchiveFailing | critical | deep-signal | active | [CNPGWALArchiveFailing.md](CNPGWALArchiveFailing.md) |
| CNPGLongRunningTransaction | warning | deep-signal | active | [CNPGLongRunningTransaction.md](CNPGLongRunningTransaction.md) |
| CNPGIdleInTransaction | warning | deep-signal | active | [CNPGIdleInTransaction.md](CNPGIdleInTransaction.md) |
| CNPGInstanceMetricsAbsent | — | chart upstream | not deployed | — |

## Template

New runbooks follow [`_TEMPLATE.md`](_TEMPLATE.md) (CNPG Meaning → Impact → Diagnosis → Mitigation).

---
_Last updated: 2026-07-18_
