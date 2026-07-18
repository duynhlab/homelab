# CNPGTransactionIDWraparoundWarning

| | |
|---|---|
| **Severity** | warning |
| **Source** | deep-signal |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | — (built-in `cnpg_pg_database_xid_age`) |
| **Grafana** | pg-maintenance |

## Meaning

`age(datfrozenxid)` exceeds **1,000,000,000** (~47% of 2³¹) for **30 minutes**
on a database. Anti-wraparound vacuum is falling behind.

## Impact

If xid age approaches 2³¹, PostgreSQL stops accepting writes to protect cluster
integrity. Long-running transactions and stalled autovacuum are the usual causes.

## Diagnosis

### PromQL

```promql
max by (cnpg_io_cluster, datname) (cnpg_pg_database_xid_age)
```

### kubectl / psql

```bash
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT datname, age(datfrozenxid) AS xid_age,
       pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
WHERE datistemplate = false
ORDER BY age(datfrozenxid) DESC;
"

kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT pid, datname, state, now() - xact_start AS age, query
FROM pg_stat_activity
ORDER BY xact_start NULLS LAST
LIMIT 10;
"
```

## Mitigation

1. Resolve [CNPGLongRunningTransaction.md](CNPGLongRunningTransaction.md) /
   [CNPGIdleInTransaction.md](CNPGIdleInTransaction.md) blockers.
2. Ensure autovacuum is running — see
   [CNPGAutovacuumFallingBehind.md](CNPGAutovacuumFallingBehind.md).
3. Manual `VACUUM FREEZE` on affected database during maintenance if needed.

## Escalation

Treat as **urgent** — escalate before critical threshold; page if trending toward
[CNPGTransactionIDWraparoundCritical.md](CNPGTransactionIDWraparoundCritical.md).
