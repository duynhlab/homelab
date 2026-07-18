# CNPGClusterHACritical

| | |
|---|---|
| **Severity** | critical |
| **Source** | chart |
| **Clusters** | `platform-db`, `product-db` (3 instances each) |

## Meaning

Fewer than **1 streaming replica** is connected to the primary — no standby for
failover. RPO/RTO at risk.

## Impact

Primary failure causes outage and potential data loss for un-replicated commits.

## Diagnosis

```promql
cnpg_collector_sync_replicas{cnpg_io_cluster="$CLUSTER"}
cnpg_collector_replica_mode{cnpg_io_cluster="$CLUSTER"}
```

```bash
kubectl get pods -n "$NAMESPACE" -l "cnpg.io/cluster=$CLUSTER"
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "SELECT * FROM pg_stat_replication;"
```

## Mitigation

1. Check replica pod events (`kubectl describe pod`).
2. NetworkPolicy blocking replication port 5432 between instances?
3. Disk full on replica — see disk runbooks (inactive on Kind).
4. CNPG will rebuild failed replicas — monitor operator reconcile.

## Escalation

**P1** until replica count restored; **P0** if primary also unhealthy.
