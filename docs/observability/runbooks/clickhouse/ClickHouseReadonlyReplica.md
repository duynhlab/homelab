# ClickHouseReadonlyReplica

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/clickhouse-alerts.yaml` |
| **Metrics** | `ClickHouseMetrics_ReadonlyReplica` — the server's own `:9363` endpoint, **per pod** |
| **Status** | active |
| **Dashboard** | ClickHouse → Server engine |
| **Local-stack** | not present — no replication in the compose stack |

## Meaning

`ClickHouseMetrics_ReadonlyReplica > 0` — a replica holds one or more
`ReplicatedMergeTree` tables in readonly mode. That happens when the replica
loses its **Keeper session**: without Keeper it cannot claim a block number, so
it refuses writes rather than diverge.

This metric is why the per-pod `:9363` scrape exists. The Altinity exporter
aggregates per CHI and has **no equivalent series at all** — it cannot tell you
which replica is readonly, or that any is.

## Impact

Writes fail **on that replica only**. The OTel Collector's clickhouse exporter
round-robins the CHI Service, so roughly a third of insert batches hit the
readonly member and retry. Its `sending_queue` and `retry_on_failure` absorb
that; sustained, it becomes drop.

Reads are unaffected — a readonly replica still serves queries, which is exactly
what makes this easy to miss from a dashboard.

## Diagnosis

```bash
PW=$(kubectl get secret -n monitoring clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)

# Which tables, on which replica -- system.replicas is LOCAL, so loop all three
for i in 0 1 2; do
  echo "--- 0-$i"
  kubectl exec -n monitoring chi-clickhouse-otel-0-$i-0 -- clickhouse-client --password="$PW" --query "
    SELECT database, table, is_readonly, active_replicas, total_replicas, queue_size
    FROM system.replicas WHERE is_readonly"
done

# The cause is nearly always the Keeper session
kubectl exec -n monitoring chi-clickhouse-otel-0-0-0 -- clickhouse-client --password="$PW" --query "
  SELECT name, host, is_expired, session_uptime_elapsed_seconds FROM system.zookeeper_connection"
```

`is_expired = 1` confirms it. `session_timeout_ms` is `30000`, so a Keeper blip
longer than 30 seconds is enough.

### PromQL

```promql
ClickHouseMetrics_ReadonlyReplica > 0
max by (replica) (ClickHouseMetrics_ReadonlyReplica)     # which pod
```

## Mitigation

1. **Fix Keeper first** — this is a symptom.
   [ClickHouseKeeperNoLeader](ClickHouseKeeperNoLeader.md) /
   [ClickHouseKeeperQuorumDegraded](ClickHouseKeeperQuorumDegraded.md).
2. Once Keeper is healthy the replica normally re-establishes its session and
   leaves readonly on its own. Verify with `system.replicas`, not with the
   alert clearing.
3. `SYSTEM RESTART REPLICA <db>.<table>` on the affected pod forces a
   re-registration if it does not recover by itself. Restarting the pod also
   works and is less surgical.
4. Do not route writes away from it manually. The Service and the exporter's
   retry already handle it, and hand-editing endpoints leaves state Flux will
   revert.

## Escalation

Warning. Escalate if more than one replica is readonly, or if it persists after
Keeper is confirmed healthy — that combination suggests a per-table problem
rather than a session problem.

## Related

- [ClickHouseKeeperNoLeader](ClickHouseKeeperNoLeader.md) — the usual cause.
- [ClickHouseZooKeeperExceptions](ClickHouseZooKeeperExceptions.md) — the noisier
  early warning from the same root.
- [ClickHouseAllReplicasUnreachable](ClickHouseAllReplicasUnreachable.md) — if
  all three go readonly the store is effectively write-down, though this alert
  stays warning-level.

---
_Last updated: 2026-09-05 — created; the clickhouse alert group had no runbooks at all_
