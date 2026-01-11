# Monitoring Stack

## Overview

The monitoring stack includes:
- **Prometheus Operator**: Metrics collection and storage
- **Grafana Operator**: Dashboards and visualization
- **Metrics Server**: Resource metrics API

## Installation Method

Currently installed via Helm (transitioning to pure Kustomize in future phases):

```bash
# Prometheus Operator
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values k8s/prometheus/values.yaml

# Grafana Operator
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install grafana-operator grafana/grafana-operator \
  --namespace monitoring \
  --values k8s/grafana-operator/values.yaml

# Metrics Server
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --values k8s/metrics/metrics-server-values.yaml
```

## Flux Integration

For Phase 1, we'll use Flux HelmRelease CRDs to manage Helm installations declaratively.

## Files

See existing configurations:
- `k8s/prometheus/values.yaml`
- `k8s/grafana-operator/values.yaml`
- `k8s/metrics/metrics-server-values.yaml`
