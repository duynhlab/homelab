# CNPGLongRunningTransaction

| | |
|---|---|
| **Severity** | warning |
| **Source** | deep-signal |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | `pg_long_running_transactions` |
| **Grafana** | pg-maintenance (Long transactions row) |

## Meaning

Fires when `cnpg_pg_long_running_transactions_oldest_transaction_seconds` > **300**
(5m) for **5 minutes** — the oldest open client transaction on the instance.

## Impact

Long transactions prevent vacuum from reclaiming dead tuples, hold row locks,
and delay xid freezing → bloat and wraparound risk. One bad migration or ORM
session can degrade the whole database.

## Diagnosis

### PromQL

```promql
max by (cnpg_io_cluster) (cnpg_pg_long_running_transactions_oldest_transaction_seconds)
max by (cnpg_io_cluster) (cnpg_pg_long_running_transactions_longest_active_query_seconds)
```

### kubectl / psql

```bash
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT pid, datname, usename, state,
       now() - xact_start AS xact_age,
       now() - query_start AS query_age,
       left(query, 200) AS query
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND xact_start IS NOT NULL
ORDER BY xact_start
LIMIT 20;
"
```

## Mitigation

1. Contact owning team; prefer commit/rollback over `pg_terminate_backend`.
2. For confirmed stuck sessions: `SELECT pg_cancel_backend(pid)` then
   `pg_terminate_backend(pid)` if needed.
3. Set `idle_in_transaction_session_timeout` if idle-in-txn is the pattern —
   see [CNPGIdleInTransaction.md](CNPGIdleInTransaction.md).
4. Review deploy windows — migrations should not hold open transactions.

## Escalation

Page if xact age >30m or co-fires with wraparound / autovacuum alerts.
