# CNPG Prometheus rules (chart baseline)

Upstream source: [cloudnative-pg/charts — `charts/cluster/prometheus_rules/`](https://github.com/cloudnative-pg/charts/tree/main/charts/cluster/prometheus_rules). Those paths contain **Helm template fragments**, not apply-ready Kubernetes YAML. This directory stores **`PrometheusRule` CRs** split **one file per upstream fragment** (same basename, e.g. `cluster-offline.yaml`) for review parity with the chart.

## Render baseline (maintainers)

Pinned chart: **`cluster` Helm chart `0.6.0`** (`helm repo add cnpg https://cloudnative-pg.github.io/charts`).

```bash
helm template x cnpg/cluster --version 0.6.0 -n product \
  --set cluster.monitoring.enabled=true \
  --set cluster.instances=3 \
  --set fullnameOverride=cnpg-db \
  | yq eval 'select(.kind == "PrometheusRule")' -
```

`fullnameOverride=cnpg-db` must match the CloudNativePG `Cluster` name [`cnpg-db`](../../../databases/clusters/cnpg-db/instance.yaml) so `pod=~"cnpg-db-([1-9][0-9]*)$"` is correct.

## File ↔ upstream map

| File | Alert (first rule) |
|------|-------------------|
| `cluster-offline.yaml` | `CNPGClusterOffline` |
| `cluster-high_replication_lag.yaml` | `CNPGClusterHighReplicationLag` |
| `cluster-physical_replication_lag-*.yaml` | Physical replication lag warning/critical |
| `cluster-high_connection-*.yaml` | High connections warning/critical |
| `cluster-ha-*.yaml` | HA warning/critical |
| `cluster-low_disk_space-*.yaml` | Low disk (kubelet volume metrics) |
| `cluster-instances_on_same_node.yaml` | Pod colocation |
| `cluster-zone_spread-warning.yaml` | Zone spread |
| `cluster-logical_replication_*.yaml` | Logical replication |

## Extra CNPG rules (not in chart fragments)

- `cluster-fenced.yaml` — `CnpgClusterFenced` (kept when splitting from legacy `postgres-alerts`).
- `cluster-wal-size-high.yaml` — `PostgresWALSizeHigh` (CNPG WAL directory size).

## Metrics inventory

Before enabling rules that depend on **kube-state-metrics / kubelet volume stats**, confirm series exist in VictoriaMetrics (`kube_pod_info`, `kubelet_volume_stats_*`, `kube_pod_spec_volumes_persistentvolumeclaims_info`).

**Label names (KSM + VMAgent)** — Series `kube_pod_info` use **`exported_namespace`** and **`exported_pod`** for the workload (the `pod` label names the kube-state-metrics scrape target). Rules `cluster-instances_on_same_node` and `cluster-zone_spread-warning` use those labels in PromQL (chart upstream uses `namespace`/`pod`, which do not match this setup). Their entries in [`../kustomization.yaml`](../kustomization.yaml) are **commented by default** in homelab; uncomment to deploy the rules when ready (checklist below).

**Zone spread** — Needs `kube_node_labels` with `label_topology_kubernetes_io_zone`, enabled by uncommenting `metricLabelsAllowlist` in [`kube-state-metrics`](../../../../../controllers/metrics/kube-state-metrics.yaml). In this repo that block is **commented by default** (Kind/homelab has no real zone labels). **Production-ready:** after nodes are labeled per AZ (e.g. `topology.kubernetes.io/zone`), uncomment the allowlist, reconcile Flux, and confirm `kube_node_labels{label_topology_kubernetes_io_zone!=""} > 0` in VictoriaMetrics before relying on `CNPGClusterZoneSpreadWarning`.

**Low disk (`cluster-low_disk_space-*.yaml`)** — `kubelet_volume_stats_*` are emitted on the kubelet **`/metrics`** endpoint (volume stats collector), not on `/metrics/cadvisor`. VMAgent must scrape kubelet via `VMNodeScrape` (see [`vmnodescrape-kubelet.yaml`](../../../victoriametrics/vmnodescrape-kubelet.yaml): jobs `kubelet-volume-stats` and `kubelet-cadvisor`). If `count(kubelet_volume_stats_available_bytes)` is still zero, the kubelet may not be publishing per-PVC volume stats (for example when the stats summary has no `pvcRef` for volumes — driver / environment dependent).

## CNPG metrics stability note

`cnpg_collector_up` and related series depend on exporter scrape health. If `/metrics` returns HTTP 500 due to duplicate metric labelsets, CNPG health alerts (for example `CNPGClusterOffline`) can fire falsely even when pods are running. The CNPG custom query config should scope `pg_stat_statements` per `current_database()` to avoid duplicate collections across target databases.
