#!/bin/bash
set -euo pipefail

echo "=== Deploying Monitoring Stack ==="

echo "Ensuring 'monitoring' namespace exists..."
kubectl get namespace monitoring >/dev/null 2>&1 || kubectl create namespace monitoring
echo "1. Deploying Prometheus..."
kubectl apply -f k8s/prometheus/

# Wait for Prometheus
echo "Waiting for Prometheus to be ready..."
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s || true

# Deploy or upgrade Grafana Operator + resources
echo "2. Installing/Upgrading Grafana Operator (Helm)..."
if command -v helm >/dev/null 2>&1; then
  helm repo add grafana-operator https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true
  helm upgrade --install grafana-operator grafana-operator/grafana-operator \
    --namespace monitoring \
    --create-namespace \
    -f k8s/grafana-operator/values.yaml
else
  echo "⚠️  Helm is not installed. Please install the operator manually:"
  echo "    See k8s/grafana-operator/README.md"
fi

echo "3. Applying Grafana CRDs (instance, datasource, dashboards)..."
kubectl apply -f k8s/grafana-operator/grafana.yaml
kubectl apply -f k8s/grafana-operator/datasource-prometheus.yaml
kubectl apply -k k8s/grafana-operator/dashboards/
echo "Waiting for Grafana Operator and Grafana instance to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana-operator -n monitoring --timeout=60s || true
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=60s || true

# Check status
echo ""
echo "=== Monitoring Stack Status ==="
kubectl get pods -n monitoring
kubectl get svc -n monitoring

echo ""
echo "=== Grafana Operator Resources ==="
kubectl get grafana -n monitoring
kubectl get grafanadatasource -n monitoring
kubectl get grafanadashboard -n monitoring

echo ""
echo "✓ Monitoring stack deployed successfully!"
echo "Prometheus: http://localhost:9090"
echo "Grafana:    http://localhost:3000 (anonymous access enabled)"

