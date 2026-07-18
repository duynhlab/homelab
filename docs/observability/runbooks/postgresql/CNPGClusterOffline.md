# CNPGClusterOffline

| | |
|---|---|
| **Severity** | critical |
| **Source** | chart |
| **Clusters** | `platform-db`, `product-db` |
| **Grafana** | CloudNativePG Cluster Overview |

## Meaning

No ready CNPG instances report `cnpg_collector_up` — the cluster appears fully
offline to monitoring for **5 minutes**.

## Impact

Applications cannot reach the database. Total outage for dependent services.
Data-loss risk if primary failed uncleanly without sync replica acknowledgment.

## Diagnosis

> **Start here:** [Emergency recovery](../../../databases/010.4-emergency-recovery.md)

### False positive branch

Exporter scrape can fail with HTTP 500 while Postgres is healthy — duplicate
metric labelsets from mis-scoped custom queries (see
[`cnpg/README.md`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/cnpg/README.md)).
Verify pods before declaring outage:

```bash
kubectl get pods -n "$NAMESPACE" -l "cnpg.io/cluster=$CLUSTER" -o wide
kubectl exec -n "$NAMESPACE" "${CLUSTER}-1" -c postgres -- curl -s -o /dev/null -w '%{http_code}' http://localhost:9187/metrics
```

### PromQL

```promql
cnpg_collector_up{cnpg_io_cluster="$CLUSTER"}
up{job=~".*cnpg.*", namespace="$NAMESPACE"}
```

### kubectl

```bash
kubectl get cluster -n "$NAMESPACE" "$CLUSTER"
kubectl logs -n "$NAMESPACE" "${CLUSTER}-1" -c postgres --tail=100
kubectl logs -n cloudnative-pg -l app.kubernetes.io/name=cloudnative-pg --tail=50
```

## Mitigation

1. Follow [Emergency recovery](../../../databases/010.4-emergency-recovery.md)
   decision tree (availability vs integrity).
2. CNPG auto-failover usually recovers single-node loss — watch `kubectl cnpg
   status` if plugin installed.
3. If exporter false positive — fix custom query ConfigMap scope, reload metrics.

## Escalation

**P0 incident** — declare IC immediately per emergency recovery playbook.
