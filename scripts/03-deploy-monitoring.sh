#!/bin/bash
set -euo pipefail

echo "=== Deploying Monitoring Stack with Prometheus Operator ==="

# Ensure monitoring namespace exists
echo "Ensuring 'monitoring' namespace exists..."
kubectl get namespace monitoring >/dev/null 2>&1 || kubectl create namespace monitoring

# Label microservice namespaces for ServiceMonitor discovery
echo "1. Labeling microservice namespaces for monitoring..."
NAMESPACES=("auth" "user" "product" "cart" "order" "review" "notification" "shipping")
for ns in "${NAMESPACES[@]}"; do
  if kubectl get namespace "$ns" >/dev/null 2>&1; then
    kubectl label namespace "$ns" monitoring=enabled --overwrite
    echo "  ✓ Labeled namespace: $ns"
  else
    echo "  ⚠ Namespace $ns does not exist yet (will be created when deploying microservices)"
  fi
done

# Install Prometheus Operator via kube-prometheus-stack
echo "2. Installing Prometheus Operator (kube-prometheus-stack)..."
if command -v helm >/dev/null 2>&1; then
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true
  
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    -f k8s/prometheus/values.yaml \
    --wait \
    --timeout 5m
  
  echo "  ✓ Prometheus Operator installed"
else
  echo "  ✗ Helm is required but not installed!"
  exit 1
fi

# Wait for Prometheus Operator CRDs to be ready
echo "3. Waiting for Prometheus Operator CRDs..."
sleep 10

# Apply ServiceMonitor for microservices
echo "4. Applying ServiceMonitor for microservices..."
kubectl apply -f k8s/prometheus/servicemonitor-microservices.yaml
echo "  ✓ ServiceMonitor created"

# Deploy Grafana Operator + resources
echo "5. Installing/Upgrading Grafana Operator..."
helm repo add grafana-operator https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true
helm upgrade --install grafana-operator grafana-operator/grafana-operator \
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
echo "✓ Monitoring stack deployed successfully!"
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
