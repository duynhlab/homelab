## Grafana Operator Installation

This project now manages Grafana (and all dashboards/datasources) by using the [Grafana Operator](https://github.com/grafana-operator/grafana-operator).

### Install the operator via Helm

```bash
helm repo add grafana-operator https://grafana.github.io/helm-charts
helm repo update

# Install the operator in the monitoring namespace (creates namespace if needed)
helm upgrade --install grafana-operator grafana-operator/grafana-operator \
  --namespace monitoring \
  --create-namespace \
  -f k8s/grafana-operator/values.yaml
```

The provided `values.yaml` scopes the operator to only watch the `monitoring` namespace (where Prometheus and Grafana already live).

### Apply Grafana resources

After the operator is running, apply the CRDs that describe the Grafana instance, datasource, and dashboards:

```bash
# Grafana instance managed by the operator
kubectl apply -f k8s/grafana-operator/grafana.yaml

# Prometheus datasource (UID: prometheus)
kubectl apply -f k8s/grafana-operator/datasource-prometheus.yaml

# Dashboard ConfigMap + GrafanaDashboard CRs
kubectl apply -f k8s/grafana-operator/dashboards/
```

Once the operator reconciles these resources, Grafana will automatically contain:

- The main microservices monitoring dashboard
- Sloth SLO Overview (ID 14643)
- Sloth SLO Detailed (ID 14348)

### Removing the legacy Grafana deployment

After verifying that the operator-managed Grafana instance works, remove the old deployment and ConfigMaps:

```bash
kubectl delete deployment grafana -n monitoring --ignore-not-found
kubectl delete configmap grafana-dashboards-config grafana-datasources grafana-dashboard-json -n monitoring --ignore-not-found
```

> Tip: keep the old manifests in Git history for reference—only remove from the live cluster once the new setup is confirmed.

