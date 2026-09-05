# ClickHouseKeeperQuorumDegraded

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/clickhouse-alerts.yaml` |
| **Metrics** | `ClickHouseAsyncMetrics_KeeperSyncedFollowers` — CHK `:7000` |
| **Status** | active |
| **Dashboard** | ClickHouse → Server engine |
| **Local-stack** | not present — no Keeper in the compose stack |

## Meaning

```promql
(max(ClickHouseAsyncMetrics_KeeperSyncedFollowers) OR on() vector(0)) < 2
```

The leader has fewer than 2 synced followers. On a 3-node quorum healthy is
exactly **2**, so this fires the moment one member falls behind or drops.

`max()` is used because **only the leader reports a real follower count** —
followers report zero, and a `sum` or `avg` would be meaningless. The
`OR on() vector(0)` again makes total series loss fire rather than go silent.

## Impact

None yet, and that is the point of the warning. Quorum on 3 nodes survives one
loss: with 2 synced followers you can lose one; with 1 you are at the edge, and
losing another means no leader and no commits
([ClickHouseKeeperNoLeader](ClickHouseKeeperNoLeader.md)).

Treat it as the redundancy alarm, not an outage.

## Diagnosis

```bash
kubectl get pods -n monitoring -l clickhouse-keeper.altinity.com/chk=keeper -o wide
kubectl get chk -n monitoring keeper

# Which member is behind, and why
for i in 0 1 2; do
  echo "--- keeper-$i"
  kubectl logs -n monitoring keeper-$i --tail=40 | grep -iE 'raft|sync|snapshot|behind'
done
```

### PromQL

```promql
max(ClickHouseAsyncMetrics_KeeperSyncedFollowers)      # healthy = 2
count(ClickHouseAsyncMetrics_KeeperIsLeader)           # should be 3 pods reporting
count(ClickHouseAsyncMetrics_KeeperIsLeader == 1)      # should be exactly 1
```

## Mitigation

1. A member restarting or catching up after a restart produces this transiently —
   confirm it clears rather than acting immediately.
2. If a pod is `Pending`, it is a scheduling problem; the keeper PVCs are small
   but they are `standard` local-path, so a pod is bound to its node.
3. Do not scale the CHK to change quorum size as a fix. Quorum arithmetic on
   raft is not something to tune during an incident.

## Escalation

Warning. It becomes urgent if it persists — a 3-node quorum sitting at 1 synced
follower has no margin left.

## Related

- [ClickHouseKeeperNoLeader](ClickHouseKeeperNoLeader.md) — what this becomes.
- [ClickHouseReadonlyReplica](ClickHouseReadonlyReplica.md),
  [ClickHouseZooKeeperExceptions](ClickHouseZooKeeperExceptions.md) — server-side
  effects.

---
_Last updated: 2026-09-05 — created; the clickhouse alert group had no runbooks at all_
