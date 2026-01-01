#!/bin/bash
set -euo pipefail

echo "=== Deploying Monitoring Stack (Prometheus + Grafana + Metrics Infrastructure) ==="
echo "This includes: kube-prometheus-stack (with kube-state-metrics) + metrics-server"
echo ""

# Ensure monitoring namespace exists
echo "Ensuring 'monitoring' namespace exists..."
kubectl get namespace monitoring >/dev/null 2>&1 || kubectl create namespace monitoring

# Install Prometheus Operator via kube-prometheus-stack
echo "Step 1: Installing kube-prometheus-stack v80.0.0 (includes kube-state-metrics)..."
if command -v helm >/dev/null 2>&1; then
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true
  
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --version 80.0.0 \
    --namespace monitoring \
    --create-namespace \
    -f k8s/prometheus/values.yaml \
    --wait \
    --timeout 5m
  
  echo "  SUCCESS: Prometheus Operator v80.0.0 installed (includes kube-state-metrics)"
else
  echo "  ERROR: Helm is required but not installed!"
  exit 1
fi

# Install metrics-server (for kubectl top and HPA)
echo "2. Installing metrics-server..."
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  -f k8s/metrics/metrics-server-values.yaml \
  --wait \
  --timeout 2m

echo "  SUCCESS: metrics-server installed"
echo ""

# Wait for Prometheus Operator CRDs to be ready
echo "3. Waiting for Prometheus Operator CRDs..."
sleep 10

# Apply ServiceMonitors
echo "4. Applying ServiceMonitors..."
if [ -d "k8s/prometheus/servicemonitors" ]; then
    kubectl apply -f k8s/prometheus/servicemonitors/
    echo "  SUCCESS: ServiceMonitors deployed"
else
    echo "  WARN: k8s/prometheus/servicemonitors directory not found, skipping ServiceMonitor deployment"
fi

# Deploy Grafana Operator + resources
echo "5. Installing/Upgrading Grafana Operator v5.20.0..."
helm repo add grafana-operator https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true
helm upgrade --install grafana-operator grafana-operator/grafana-operator \
  --version v5.20.0 \
  --namespace monitoring \
  --create-namespace \
  -f k8s/grafana-operator/values.yaml

echo "6. Applying Grafana CRDs (instance, datasources, dashboards)..."
kubectl apply -f k8s/grafana-operator/grafana.yaml
kubectl apply -f k8s/grafana-operator/datasource-prometheus.yaml
kubectl apply -f k8s/grafana-operator/datasource-tempo.yaml
kubectl apply -f k8s/grafana-operator/datasource-loki.yaml
kubectl apply -f k8s/grafana-operator/datasource-pyroscope.yaml
kubectl apply -k k8s/grafana-operator/dashboards/

echo "Waiting for Grafana Operator and Grafana instance to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana-operator -n monitoring --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=120s || true

# Check status
echo ""
echo "=== Monitoring Stack Status ==="
kubectl get pods -n monitoring
echo ""
kubectl get svc -n monitoring

echo ""
echo "=== Prometheus Operator Resources ==="
kubectl get prometheus -n monitoring
kubectl get servicemonitors -n monitoring
kubectl get prometheusrules -n monitoring

echo ""
echo "=== Grafana Operator Resources ==="
kubectl get grafana -n monitoring
kubectl get grafanadatasources -n monitoring
kubectl get grafanadashboards -n monitoring

echo ""
echo "SUCCESS: Monitoring stack deployed successfully!"
echo "  - Prometheus Operator with kube-state-metrics"
echo "  - Grafana Operator with dashboards"
echo "  - metrics-server for kubectl top / HPA"
echo ""
echo "Access URLs (after port-forward):"
echo "  Prometheus: http://localhost:9090"
echo "  Grafana:    http://localhost:3000 (anonymous access enabled)"
echo ""
echo "Next steps:"
echo "  1. Deploy microservices: ./scripts/06-deploy-microservices.sh"
echo "  2. Deploy SLO: ./scripts/08-deploy-slo.sh"
echo "  3. Setup access: ./scripts/09-setup-access.sh"
echo ""
