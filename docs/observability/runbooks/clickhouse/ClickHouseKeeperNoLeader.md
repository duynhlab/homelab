# ClickHouseKeeperNoLeader

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/clickhouse-alerts.yaml` |
| **Metrics** | `ClickHouseAsyncMetrics_KeeperIsLeader` — the CHK's own `:7000` Prometheus endpoint |
| **Status** | active |
| **Dashboard** | ClickHouse → Server engine |
| **Local-stack** | not present — local-stack runs single-node with no Keeper |

## Meaning

```promql
(count(ClickHouseAsyncMetrics_KeeperIsLeader == 1) OR on() vector(0)) == 0
```

The 3-node ClickHouse Keeper quorum has **no leader**. Without a leader, raft
cannot commit, so replicated DDL and replication bookkeeping stop.

Note the `OR on() vector(0)`. That is deliberate and load-bearing: it makes the
alert fire when the Keeper series **disappear entirely**, not only when they
report zero. Without it, losing the whole quorum would produce silence — the
same blind spot [ClickHouseAllReplicasUnreachable](ClickHouseAllReplicasUnreachable.md)
still has for the servers.

Healthy reads exactly `1` — one leader, two followers.

## Impact

Replicas keep serving **reads**, and keep accepting inserts only for as long as
their existing Keeper sessions hold. Once a session expires the replica goes
**readonly** ([ClickHouseReadonlyReplica](ClickHouseReadonlyReplica.md)) and
refuses writes. So the visible sequence is: no leader → sessions expire →
inserts fail → the OTel exporter backpressures.

The `otel` database is `ENGINE = Replicated`, so its table DDL propagates through
Keeper. With no leader, the `clickhouse-schema` Job cannot create anything and a
replica joining fresh cannot initialise its tables.

## Diagnosis

```bash
kubectl get chk -n monitoring keeper
kubectl get pods -n monitoring -l clickhouse-keeper.altinity.com/chk=keeper -o wide
kubectl logs -n monitoring keeper-0 --tail=100 | grep -iE 'raft|leader|election'
```

From the server side — the column names were verified on 26.7, do not guess them:

```sql
DESCRIBE TABLE system.zookeeper_connection;
SELECT name, host, is_expired, session_timeout_ms, session_uptime_elapsed_seconds
FROM system.zookeeper_connection;
```

`is_expired = 1` is what turns a replica readonly. `session_timeout_ms` is
`30000` here, which sets how long you have before that happens.

### PromQL

```promql
(count(ClickHouseAsyncMetrics_KeeperIsLeader == 1) OR on() vector(0)) == 0
count(ClickHouseAsyncMetrics_KeeperIsLeader)          # should be 3 — fewer means pods are gone
max(ClickHouseAsyncMetrics_KeeperSyncedFollowers)     # healthy >= 2
```

## Mitigation

1. Quorum needs 2 of 3. Count the running keeper pods first — with only one up,
   no election can complete and the fix is to get a second back, not to restart
   the survivor.
2. Restart the pod that is unhealthy, not the leader-less quorum wholesale.
3. `clickhouse-keeper-local` is a **separate Flux wave** that `clickhouse-local`
   depends on, precisely so the CHI is never applied before Keeper exists. If
   both are being created, order matters and waiting is correct.
4. The CHI references the CHK **by name** and resolves it **once**, failing open:
   if Keeper was absent at resolve time the rendered config gets an empty
   `<zookeeper>` and never re-resolves. If Keeper is healthy but servers still
   cannot reach it, check that the servers actually have keeper endpoints in
   their config — a restart of the server pods forces a re-render.

## Escalation

Critical. Writes are on a timer measured by `session_timeout_ms` (30s), so this
degrades quickly rather than staying stable.

## Related

- [ClickHouseKeeperQuorumDegraded](ClickHouseKeeperQuorumDegraded.md) — the
  warning that usually precedes this.
- [ClickHouseReadonlyReplica](ClickHouseReadonlyReplica.md) — the consequence.
- [ClickHouseZooKeeperExceptions](ClickHouseZooKeeperExceptions.md) — the
  server-side symptom of Keeper trouble.

---
_Last updated: 2026-09-05 — created; the clickhouse alert group had no runbooks at all_
