# CNPGClusterLogicalReplicationErrors

| | |
|---|---|
| **Severity** | warning |
| **Source** | chart |
| **Status** | **Inactive on homelab** — no logical replication subscriptions configured |

## Meaning

Logical replication apply/sync error counters increasing.

## Impact

Subscriber diverges from publisher — downstream consumers see inconsistent data.

## Diagnosis

When subscriptions exist:

```promql
increase(cnpg_pg_stat_subscription_apply_error_count[5m])
```

```bash
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT subname, subenabled, latest_error FROM pg_subscription;
"
```

## Mitigation

1. Read `latest_error` on subscription — fix schema drift or conflict policy.
2. Resync subscription per CNPG logical replication docs.

## Escalation

Page when active in production if errors persist >15m.
