# CNPGClusterHighReplicationLag

Investigate a chart-generated time-lag warning without mistaking an idle
standby for a stale standby.

| Quick facts | |
|---|---|
| **Severity** | warning |
| **Category** | database / replication |
| **Source** | `prometheusrules/postgres/{cnpg,cnpg-platform-db}/cluster-high_replication_lag.yaml` |
| **Expression** | `max(cnpg_pg_replication_lag{...}) > 1` for 5 minutes |
| **Clusters** | `product-db`, `platform-db` |
| **Status** | Deployed chart rule; known idle-standby false-positive risk |
| **Preferred evidence** | Byte lag and WAL positions from the physical-replication-lag runbooks |
| **Dashboard** | Databases → CloudNativePG cluster overview |

## Meaning

The largest selected standby reports more than one second since its last
replayed transaction for five minutes. The metric is derived from
`now() - pg_last_xact_replay_timestamp()`. On a quiet primary there may be no
new transaction to replay, so elapsed time grows even when the standby has
received and replayed every available WAL record.

This alert therefore detects a time observation, not conclusive replication
backlog. Confirm byte/LSN lag before treating it as an incident.

## Impact

- If WAL positions differ and the gap grows, reads from the standby may be stale
  and failover may increase the recovery-point loss window.
- If positions agree and the primary is idle, there is no replication impact;
  this is a false positive from the metric's idle semantics.
- Persistent real lag can retain WAL, increase storage pressure, and reduce HA
  confidence.

## Diagnosis

Start from the alert's `namespace` and `cnpg_cluster` labels. Do not assume the
pod selected by the regex is the only affected standby.

### PromQL

```promql
cnpg_pg_replication_lag{namespace="$namespace",cnpg_io_cluster="$cluster"}
```

Compare it with the byte-lag metric used by the physical replication rules:

```promql
cnpg_pg_replication_slots_pg_wal_lsn_diff{namespace="$namespace",cnpg_io_cluster="$cluster"}
```

If time lag rises while byte lag stays at zero, classify the alert as idle
metric semantics and do not restart or fail over the cluster.

### PostgreSQL

Run bounded read-only checks on the current primary:

```sql
SET statement_timeout = '5s';

SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS replay_gap,
    write_lag,
    flush_lag,
    replay_lag
FROM pg_stat_replication
ORDER BY application_name;
```

Then check CNPG instance roles and conditions:

```bash
kubectl -n "$namespace" get cluster "$cluster" -o wide
kubectl -n "$namespace" get pods -l "cnpg.io/cluster=$cluster" -o wide
```

For real lag, correlate network/storage pressure, long-running replay conflicts,
WAL archive health, and primary write rate. For an idle false positive, capture
the agreeing LSNs and alert value as rule-maintenance evidence.

## Mitigation

1. **Idle false positive:** take no cluster action. Silence only for a bounded
   period if notification noise is harmful, and record the evidence.
2. **Small stable byte lag:** observe across two scrape intervals and check that
   replay advances when new writes occur.
3. **Growing byte lag:** remove the measured resource bottleneck or conflicting
   standby query using the physical-replication-lag runbook.
4. Do not fail over merely to clear this time-based alert; a lagging standby is
   a poor promotion candidate.

The durable correction is to remove or replace this generated duplicate at its
chart-generation source. Do not hand-edit the generated expression.

## Recovery validation

- WAL receive/flush/replay positions converge after a known write.
- Byte lag is stable at zero or drains toward zero.
- CNPG reports the expected primary and ready standbys.
- No WAL-retention or archive alert appeared.
- If this was idle-only, the incident record says false positive rather than
  claiming a replication repair.

## Escalation

Escalate when byte lag grows for ten minutes, a standby leaves streaming state,
WAL storage runway is threatened, or no healthy promotion candidate remains.
Attach sanitized positions, byte-lag history, write rate, wait events, and CNPG
conditions.

## Related

- [CNPGClusterPhysicalReplicationLagWarning](CNPGClusterPhysicalReplicationLagWarning.md)
- [CNPGClusterPhysicalReplicationLagCritical](CNPGClusterPhysicalReplicationLagCritical.md)
- [CNPGClusterStandbyNotStreaming](CNPGClusterStandbyNotStreaming.md)
- [Replication fundamentals](../../../databases/fundamentals/replication.md)
- [Database troubleshooting](../../../databases/observability-and-troubleshooting.md)

---
_Last updated: 2026-09-09 — added because both deployed CNPG profiles referenced a missing runbook; idle-time semantics are called out explicitly._
