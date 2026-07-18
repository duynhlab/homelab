# CNPGIdleInTransaction

| | |
|---|---|
| **Severity** | warning |
| **Source** | deep-signal |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | `pg_long_running_transactions` |
| **Grafana** | pg-maintenance |

## Meaning

Fires when `cnpg_pg_long_running_transactions_oldest_idle_in_transaction_seconds`
> **300** for **5 minutes** — a client opened a transaction (`BEGIN`) and went
idle without committing.

## Impact

Idle-in-transaction is the classic autovacuum killer: dead tuples on touched
tables cannot be reclaimed while the transaction remains open. Often caused by
connection pool bugs, ORMs leaving transactions open, or interactive psql sessions.

## Diagnosis

### PromQL

```promql
max by (cnpg_io_cluster) (cnpg_pg_long_running_transactions_oldest_idle_in_transaction_seconds)
cnpg_pg_long_running_transactions_idle_in_transaction_count
```

### kubectl / psql

```bash
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT pid, datname, usename, client_addr, application_name,
       now() - xact_start AS idle_in_txn_for,
       left(query, 200) AS last_query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY xact_start;
"
```

Trace application name to service pod / pooler connection.

## Mitigation

1. Terminate confirmed orphan sessions after team ack:
   `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle in transaction' AND ...`
2. Enable or lower `idle_in_transaction_session_timeout` on the cluster (CNPG
   `postgresql.parameters`).
3. Fix client code — ensure defer/commit on all paths; check PgDog transaction
   pooling compatibility with prepared statements.
4. See [CNPGAutovacuumFallingBehind.md](CNPGAutovacuumFallingBehind.md) if bloat
   already built up.

## Escalation

Ticket for single stray session; page if count >10 or autovacuum alert co-fires.
