#!/bin/bash
set -e

echo "=== Deploying Monitoring Stack ==="

# Deploy Prometheus (simple deployment)
echo "1. Deploying Prometheus..."
kubectl apply -f k8s/prometheus/

# Wait for Prometheus
echo "Waiting for Prometheus to be ready..."
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s || true

# Create Grafana dashboard ConfigMap
echo "2. Creating Grafana dashboard ConfigMap..."
kubectl create configmap grafana-dashboard-json --from-file=grafana-dashboard.json -n monitoring --dry-run=client -o yaml | kubectl apply -f -

# Deploy Grafana
echo "3. Deploying Grafana..."
kubectl apply -f k8s/grafana/

# Wait for Grafana
echo "Waiting for Grafana to be ready..."
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=120s || true

# Check status
echo ""
echo "=== Monitoring Stack Status ==="
kubectl get pods -n monitoring
kubectl get svc -n monitoring
# kubectl get servicemonitor -n monitoring

echo ""
echo "✓ Monitoring stack deployed successfully!"
echo "Prometheus: http://localhost:9090"
echo "Grafana:    http://localhost:3000 (admin/admin)"

