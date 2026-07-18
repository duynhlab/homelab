# CNPGDeadlocksIncreasing

| | |
|---|---|
| **Severity** | warning |
| **Source** | deep-signal |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | — (built-in `cnpg_pg_stat_database_deadlocks`) |
| **Grafana** | pg-maintenance |

## Meaning

Fires when `increase(cnpg_pg_stat_database_deadlocks[10m]) > 0` for **5 minutes**
on any database. PostgreSQL detected at least one deadlock cycle and aborted the
victim transaction.

## Impact

Deadlocked transactions roll back — users may see transient errors or retried
operations. Recurring deadlocks indicate inconsistent lock ordering across
application code paths (classic multi-service bug).

## Diagnosis

### PromQL

```promql
sum by (cnpg_io_cluster, datname) (increase(cnpg_pg_stat_database_deadlocks[10m]))
```

### kubectl / psql

```bash
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT datname, deadlocks, conflicts, temp_files, temp_bytes
FROM pg_stat_database
WHERE datname NOT IN ('template0', 'template1', 'postgres')
ORDER BY deadlocks DESC;
"
```

Check Postgres logs in VictoriaLogs for `deadlock detected` detail lines (includes
the two queries involved).

## Mitigation

1. Extract deadlock graph from logs — identify tables and query order.
2. Fix application lock ordering (always lock rows in consistent key order).
3. Shorten transactions — deadlocks worsen with long-held locks; see
   [CNPGLongRunningTransaction.md](CNPGLongRunningTransaction.md).
4. Do **not** raise deadlock_timeout as a fix — it only delays detection.

## Escalation

Ticket to owning service team if pattern repeats; page if deadlocks correlate
with order/checkout error-rate alerts.
