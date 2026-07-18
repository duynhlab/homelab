# CNPGClusterLogicalReplicationStopped

| | |
|---|---|
| **Severity** | warning |
| **Source** | chart |
| **Status** | **Inactive on homelab** |

## Meaning

Subscription disabled or replication worker stuck (`cnpg_pg_stat_subscription_enabled==0`).

## Impact

Replication halted — growing backlog on publisher side.

## Diagnosis

```bash
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT * FROM pg_stat_subscription;
"
```

## Mitigation

1. Re-enable subscription after fixing error.
2. Verify slot exists on publisher: `pg_replication_slots`.

## Escalation

Page if stopped >15m when subscriptions are production-critical.
