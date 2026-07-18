# CNPGClusterZoneSpreadWarning

| | |
|---|---|
| **Severity** | warning |
| **Source** | chart |
| **Status** | **Gated** — requires KSM zone labels on nodes |

## Meaning

Fewer than **3 unique availability zones** host cluster instances (expected for
3-node HA across zones).

## Impact

Zone outage can destroy majority of cluster — data loss and extended outage.

## Diagnosis

Production checklist from [`cnpg/README.md`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/cnpg/README.md):

1. Uncomment `metricLabelsAllowlist` for `topology.kubernetes.io/zone` in kube-state-metrics.
2. Label nodes per AZ.
3. Verify `kube_node_labels{label_topology_kubernetes_io_zone!=""} > 0`.
4. Uncomment rule in postgres kustomization.

## Mitigation

1. Spread CNPG instances across zones via topology spread / node selectors.
2. Do not enable rule on Kind until real zone labels exist.

## Escalation

Production-only alert — page if armed and zone failure imminent.
