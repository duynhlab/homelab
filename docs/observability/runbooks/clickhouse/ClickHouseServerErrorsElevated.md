# ClickHouseServerErrorsElevated

| | |
|---|---|
| **Severity** | info |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/clickhouse-alerts.yaml` |
| **Metrics** | `ClickHouseErrorMetric_ALL` — the server's own `:9363` endpoint, per pod |
| **Status** | active |
| **Dashboard** | ClickHouse → Server engine (`system.errors` top-N table) |
| **Local-stack** | present — the compose stack scrapes `:9363` too |

## Meaning

```promql
max by (replica) (rate(ClickHouseErrorMetric_ALL{job="clickhouse-server"}[5m])) > 5
```

More than 5 errors/second on the worst replica for 10 minutes.

Note `max by (replica)`, not a fleet sum. That is a deliberate move from a census
to a **worst-replica outlier**: one sick replica averaged across three looks
healthy, which is how a real problem hides.

This rule previously named `chi_clickhouse_system_errors_value`, which returns
zero series — it was repaired on 2026-08-31 after its expression was finally
pasted into a query window. The `ClickHouseErrorMetric_*` family comes from the
per-pod `:9363` scrape RFC-0028 added; there are ~737 of them, one per error
code, and `_ALL` is the aggregate.

`system.errors` counts **everything**, including errors that are entirely normal
— a client sending bad SQL raises one. Rate matters, not presence.

## Impact

Usually none directly; this is a diagnostic. It matters as corroboration: a burst
here alongside a Keeper or disk alert tells you which is cause and which is
effect.

## Diagnosis

The aggregate says how many, not which. Go to `system.errors` for that:

```bash
PW=$(kubectl get secret -n monitoring clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)
for i in 0 1 2; do
  echo "--- replica 0-$i"
  kubectl exec -n monitoring chi-clickhouse-otel-0-$i-0 -- clickhouse-client --password="$PW" --query "
    SELECT name, code, value, last_error_time, substring(last_error_message,1,90) AS msg
    FROM system.errors WHERE value > 0 ORDER BY value DESC LIMIT 10"
done
```

`system.errors` is per-replica and cumulative since start — compare `value`
across replicas rather than reading one in isolation.

### PromQL

```promql
max by (replica) (rate(ClickHouseErrorMetric_ALL{job="clickhouse-server"}[5m])) > 5

# Break it down: the per-code family is where the answer is
topk(10, rate({__name__=~"ClickHouseErrorMetric_.+", job="clickhouse-server"}[5m]))
```

That per-code family is also the **cost** of this scrape: 737 metric names, and
`job="clickhouse-server"` accounts for roughly 5% of all platform series. Worth
knowing before adding more.

## Mitigation

Read the top error names first — they usually name their own fix:

| Error family | Points at |
|---|---|
| `KEEPER_EXCEPTION`, `NO_ZOOKEEPER` | [ClickHouseKeeperNoLeader](ClickHouseKeeperNoLeader.md) |
| `TOO_MANY_PARTS` | [ClickHouseTooManyParts](ClickHouseTooManyParts.md) |
| `NOT_ENOUGH_SPACE` | [ClickHouseDiskCritical](ClickHouseDiskCritical.md) |
| `TABLE_IS_READ_ONLY` | [ClickHouseReadonlyReplica](ClickHouseReadonlyReplica.md) |
| `UNKNOWN_TABLE`, `SYNTAX_ERROR` | a client, not the server — usually a dashboard query |

## Escalation

Info. It is context for another alert far more often than it is the incident.

## Related

- All four rows in the table above.
- [ClickHouseZooKeeperExceptions](ClickHouseZooKeeperExceptions.md) — the
  narrower Keeper-specific counter.

---
_Last updated: 2026-09-05 — created; the clickhouse alert group had no runbooks at all_
