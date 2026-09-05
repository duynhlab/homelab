# ClickHouseZooKeeperExceptions

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/clickhouse-alerts.yaml` |
| **Metrics** | `ClickHouseProfileEvents_ZooKeeperHardwareExceptions` — server `:9363`, per pod |
| **Status** | active — **re-enabled** by RFC-0028 |
| **Dashboard** | ClickHouse → Server engine |
| **Local-stack** | not present — no Keeper in the compose stack |

## Meaning

`rate(ClickHouseProfileEvents_ZooKeeperHardwareExceptions[5m]) > 0` — a replica
is hitting **hardware-class** Keeper exceptions: connection loss, timeouts,
session problems. Not logical errors like "node already exists", which are
routine.

This rule was written before the platform had replication and sat commented out
until RFC-0028 gave it something to watch. It is the **earliest** Keeper signal
available — it fires while sessions still hold, before
[ClickHouseReadonlyReplica](ClickHouseReadonlyReplica.md) and well before
[ClickHouseKeeperNoLeader](ClickHouseKeeperNoLeader.md).

## Impact

None yet, usually. Retries are absorbed. What it buys is warning time: the
session timeout is `30000` ms, so a replica that keeps losing its connection is
on a 30-second fuse toward readonly.

## Diagnosis

```bash
PW=$(kubectl get secret -n monitoring clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)

kubectl exec -n monitoring chi-clickhouse-otel-0-0-0 -- clickhouse-client --password="$PW" --query "
  SELECT name, host, is_expired, session_uptime_elapsed_seconds, session_timeout_ms
  FROM system.zookeeper_connection"

kubectl get pods -n monitoring -l clickhouse-keeper.altinity.com/chk=keeper -o wide
kubectl logs -n monitoring keeper-0 --tail=60 | grep -iE 'timeout|disconnect|session'
```

A short and repeatedly-resetting `session_uptime_elapsed_seconds` is the tell:
the replica keeps reconnecting.

### PromQL

```promql
rate(ClickHouseProfileEvents_ZooKeeperHardwareExceptions[5m]) > 0

# One replica or all three -- a single one points at that pod or its node
sum by (replica) (rate(ClickHouseProfileEvents_ZooKeeperHardwareExceptions[5m]))
```

## Mitigation

1. **One replica affected** → look at that pod and the node it runs on; the
   anti-affinity puts one replica per worker, so a node problem shows up as
   exactly one replica.
2. **All three affected** → the Keeper quorum is the problem, not the servers.
   Go to [ClickHouseKeeperQuorumDegraded](ClickHouseKeeperQuorumDegraded.md).
3. Do not restart replicas to "clear" it. It is a counter rate, not a stuck
   state, and restarting drops the session you are trying to keep.

## Escalation

Warning. Escalate if it is sustained rather than a blip — sustained means the
30-second fuse keeps re-lighting, and readonly follows.

## Related

- [ClickHouseKeeperQuorumDegraded](ClickHouseKeeperQuorumDegraded.md),
  [ClickHouseKeeperNoLeader](ClickHouseKeeperNoLeader.md) — the escalation path.
- [ClickHouseReadonlyReplica](ClickHouseReadonlyReplica.md) — the consequence.

---
_Last updated: 2026-09-05 — created; the clickhouse alert group had no runbooks at all_
