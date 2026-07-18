# CNPGTransactionIDWraparoundCritical

| | |
|---|---|
| **Severity** | critical |
| **Source** | deep-signal |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | — (built-in `cnpg_pg_database_xid_age`) |
| **Grafana** | pg-maintenance |

## Meaning

`age(datfrozenxid)` exceeds **1,500,000,000** for **10 minutes**. PostgreSQL will
refuse writes as age approaches 2³¹ — emergency intervention required.

## Impact

Imminent write shutdown on affected database(s). All mutating API paths for
services on that database fail.

## Diagnosis

Same as [CNPGTransactionIDWraparoundWarning.md](CNPGTransactionIDWraparoundWarning.md)
— execute immediately.

```promql
max by (cnpg_io_cluster, datname) (cnpg_pg_database_xid_age)
```

## Mitigation

1. **Immediately** identify and terminate oldest transactions blocking vacuum
   (with IC approval): `pg_terminate_backend`.
2. Run `VACUUM FREEZE VERBOSE` on affected database from primary.
3. Watch `pg_stat_progress_vacuum` and xid age until below warning threshold.
4. Open incident — follow
   [Emergency recovery](../../../databases/010.4-emergency-recovery.md).

## Escalation

**P0** — page database recovery owner and IC. Do not defer to next business day.
