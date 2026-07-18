# CNPGBlockedQueries

| | |
|---|---|
| **Severity** | warning |
| **Source** | deep-signal ([`deep-signals-alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/deep-signals-alerts.yaml)) |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | `pg_blocking_queries`, `pg_locks_count`, `pg_stat_activity_count` |
| **Grafana** | pg-maintenance (Locks & Blocking row) |

## Meaning

Fires when `cnpg_pg_blocking_queries_blocked_queries` > 0 for **10 minutes** on
a cluster. At least one client backend is waiting on a lock held by another
session (`wait_event_type = 'Lock'` in `pg_stat_activity`).

## Impact

Blocked sessions stall application requests — checkout, order placement, or auth
flows hang with growing latency. Sustained blocking often indicates a missing
index, lock-ordering bug, or a long transaction holding row-level locks. Left
unresolved, blocked sessions accumulate and connection pools saturate.

## Diagnosis

### PromQL

```promql
# Alert condition
max by (cnpg_io_cluster) (cnpg_pg_blocking_queries_blocked_queries)

# Lock mix by mode
sum by (cnpg_io_cluster, mode) (cnpg_pg_locks_count_count{cnpg_io_cluster="$CLUSTER"})

# Connection states while investigating
sum by (state) (cnpg_pg_stat_activity_count_count{cnpg_io_cluster="$CLUSTER"})
```

### Grafana

Open **pg-maintenance** → Locks & Blocking panels for `$CLUSTER`.

### kubectl / psql

```bash
export NAMESPACE=platform   # or product from alert
export CLUSTER=platform-db  # or product-db

# Who blocks whom (PG14+)
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT blocked.pid AS blocked_pid,
       blocked.usename AS blocked_user,
       blocked.datname,
       blocked.state,
       now() - blocked.query_start AS blocked_duration,
       left(blocked.query, 120) AS blocked_query,
       blocking.pid AS blocking_pid,
       blocking.usename AS blocking_user,
       left(blocking.query, 120) AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.wait_event_type = 'Lock'
ORDER BY blocked_duration DESC;
"

# Lock inventory
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT locktype, relation::regclass, mode, granted, pid
FROM pg_locks
WHERE NOT granted OR pid IN (SELECT pid FROM pg_stat_activity WHERE wait_event_type = 'Lock')
ORDER BY relation;
"
```

Check for correlated **long transactions**:
`cnpg_pg_long_running_transactions_oldest_transaction_seconds` — see
[CNPGLongRunningTransaction.md](CNPGLongRunningTransaction.md).

### VictoriaLogs

Search CNPG primary pod logs around the alert time for repeated slow queries or
migration activity (`logger: postgres` / application DDL via `pgaudit`).

## Mitigation

1. **Identify the blocking session** with `pg_blocking_pids` (above). Prefer
   fixing the root cause (commit idle transaction, finish migration) over
   `pg_terminate_backend`.
2. **If blocking pid is idle in transaction** — see
   [CNPGIdleInTransaction.md](CNPGIdleInTransaction.md); terminate only after
   confirming with the owning team.
3. **If blocking pid is an autovacuum** — usually resolves itself; check
   [CNPGAutovacuumFallingBehind.md](CNPGAutovacuumFallingBehind.md) if bloat
   is the driver.
4. **App-level deadlocks** — if `CNPGDeadlocksIncreasing` also fires, fix lock
   ordering in application code rather than killing backends repeatedly.
5. **Pooler layer** — confirm PgDog is not masking saturation:
   [PgDog operations](../../../databases/runbooks/pgdog-operations.md).

## Escalation

- **Ticket** if blocking clears within one investigation cycle and root cause is
  a one-off migration or deploy.
- **Page / incident** if blocking persists >30m, connection alerts co-fire, or
  checkout/order SLO burn-rate alerts activate.
- Do **not** mass-terminate backends during peak traffic without IC approval.
