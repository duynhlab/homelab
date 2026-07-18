# CNPGClusterInstancesOnSameNode

| | |
|---|---|
| **Severity** | warning |
| **Source** | chart |
| **Status** | **Gated** — rule commented out in [`kustomization.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/kustomization.yaml) until production |

## Meaning

More than one CNPG instance pod scheduled on the same Kubernetes node — loss of
that node loses multiple cluster members.

## Impact

Violates HA spread assumption — single node failure can take out quorum.

## Diagnosis

Production checklist from [`cnpg/README.md`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/cnpg/README.md):

1. Confirm `kube_pod_info` uses `exported_namespace` / `exported_pod` labels.
2. Uncomment rule in kustomization when ready.

```promql
count by (exported_node, cnpg_io_cluster) (
  kube_pod_info{exported_namespace="$NAMESPACE", exported_pod=~"$CLUSTER-.*"}
) > 1
```

## Mitigation

1. Add pod anti-affinity / topology spread constraints on CNPG Cluster spec.
2. Reschedule pods across nodes after constraint applied.

## Escalation

Ticket for homelab; page in production if rule armed and firing during node maintenance.
