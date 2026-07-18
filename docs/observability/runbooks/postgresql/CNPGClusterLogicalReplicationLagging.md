# CNPGClusterLogicalReplicationLagging

| | |
|---|---|
| **Severity** | warning |
| **Source** | chart |
| **Status** | **Inactive on homelab** |

## Meaning

Logical replication receipt/apply lag **>60s** or buffered bytes **>1 GB**.

## Impact

Subscribers fall behind publisher — stale reads on logical replica consumers.

## Diagnosis

```promql
cnpg_pg_stat_subscription_replication_lag_bytes
```

## Mitigation

1. Reduce publisher write burst or increase subscriber resources.
2. Check network between publisher and subscriber clusters.

## Escalation

Ticket when active; page at critical lag thresholds.
