# ClickHouseReplicaUnreachable

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/clickhouse-alerts.yaml` |
| **Metrics** | `chi_clickhouse_metric_fetch_errors` (Altinity metrics-exporter) |
| **Status** | active |
| **Dashboard** | ClickHouse → Server engine |
| **Local-stack** | not present — single-node, no operator, no exporter |

## Meaning

`max by (hostname) (chi_clickhouse_metric_fetch_errors) > 0` — at least one of
the three replicas is failing the exporter's `system.*` fetch.

This is **warning, not critical, by design.** It was critical when the store ran
1×1, where one unreachable host meant the store was down. Since RFC-0028 the
topology is 1 shard × 3 replicas, so one bad member is a degraded cluster that
still serves; the page moved to
[ClickHouseAllReplicasUnreachable](ClickHouseAllReplicasUnreachable.md).

## Impact

Reads and writes continue on the surviving replicas. What is lost is redundancy:
the store is now one failure away from the critical case, and any data the
unreachable replica has not yet replicated is temporarily single-copy.

## Diagnosis

```bash
kubectl get pods -n monitoring -l clickhouse.altinity.com/chi=clickhouse -o wide
kubectl logs -n monitoring chi-clickhouse-otel-0-<n>-0 --tail=100
```

Ask the surviving replicas what they think of the missing one — this is the
question the exporter cannot answer:

```sql
-- run on a healthy replica; system.replicas is per-replica, so loop all three
SELECT database, table, is_readonly, active_replicas, total_replicas,
       absolute_delay, queue_size
FROM system.replicas;
```

`total_replicas` below 3, or a growing `queue_size`, means the replica is genuinely
out — not just invisible to the exporter.

### PromQL

```promql
max by (hostname, fetch_type) (chi_clickhouse_metric_fetch_errors) > 0
```

## Mitigation

1. If the pod is not running, let the CHI recreate it and watch; if it does not,
   check [ClickHouseOperatorDown](ClickHouseOperatorDown.md).
2. If the pod is running but readonly, the cause is Keeper — see
   [ClickHouseReadonlyReplica](ClickHouseReadonlyReplica.md).
3. If all three answer `SELECT 1` fine, the exporter is at fault, not the store.
4. One replica per node is enforced by `requiredDuringSchedulingIgnoredDuringExecution`
   anti-affinity. A replica that is `Pending` rather than failing means no node
   is available — that is a scheduling problem, and it is deliberately visible
   rather than silently co-located.

## Escalation

Warning. Escalate only if it does not clear, or if a second replica joins it —
two of three is one step from the page.

## Related

- [ClickHouseAllReplicasUnreachable](ClickHouseAllReplicasUnreachable.md)
- [ClickHouseReadonlyReplica](ClickHouseReadonlyReplica.md)
- [ClickHouseKeeperQuorumDegraded](ClickHouseKeeperQuorumDegraded.md)

---
_Last updated: 2026-09-05 — created; the clickhouse alert group had no runbooks at all_
