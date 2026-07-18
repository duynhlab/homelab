# CNPGCheckpointPressure

| | |
|---|---|
| **Severity** | warning |
| **Source** | deep-signal |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | `pg_stat_checkpointer` |
| **Grafana** | pg-maintenance (Checkpointer row) |

## Meaning

Requested checkpoints outpace timed checkpoints for **30 minutes**:

```promql
rate(cnpg_pg_stat_checkpointer_checkpoints_req[30m])
> rate(cnpg_pg_stat_checkpointer_checkpoints_timed[30m])
```

Checkpoints are triggered by WAL volume (`max_wal_size`) rather than
`checkpoint_timeout`.

## Impact

Frequent checkpoints increase IO spikes and can amplify replication lag. Usually
a tuning signal, not an outage — unless combined with disk pressure.

## Diagnosis

### PromQL

```promql
sum by (cnpg_io_cluster) (rate(cnpg_pg_stat_checkpointer_checkpoints_req[30m]))
sum by (cnpg_io_cluster) (rate(cnpg_pg_stat_checkpointer_checkpoints_timed[30m]))
sum by (cnpg_io_cluster) (rate(cnpg_pg_stat_checkpointer_checkpoint_write_time[5m]))
```

### kubectl / psql

```bash
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT checkpoints_timed, checkpoints_req, checkpoint_write_time, buffers_checkpoint
FROM pg_stat_checkpointer;
SHOW max_wal_size;
SHOW checkpoint_timeout;
"
```

## Mitigation

1. Increase `max_wal_size` (and optionally `checkpoint_timeout`) via CNPG cluster
   parameters.
2. Reduce WAL generation — bulk loads, missing indexes, excessive updates.
3. Monitor [PostgresWALSizeHigh.md](PostgresWALSizeHigh.md) and replication lag
   runbooks if WAL piles up.

## Escalation

Ticket for tuning; page if disk critical or offline alerts co-fire.
