#!/bin/bash
set -e

echo "=== Reloading Grafana Dashboard ==="

# Delete existing ConfigMap first
echo "1. Deleting existing Grafana dashboard ConfigMap..."
kubectl delete configmap grafana-dashboard-json -n monitoring --ignore-not-found=true

# Create ConfigMap with latest dashboard JSON
echo "2. Creating Grafana dashboard ConfigMap..."
kubectl create configmap grafana-dashboard-json \
  --from-file=grafana-dashboard.json \
  -n monitoring

# Restart Grafana to reload dashboard
echo "3. Restarting Grafana to reload dashboard..."
kubectl rollout restart deployment/grafana -n monitoring

# Wait for Grafana to be ready
echo "4. Waiting for Grafana to be ready..."
kubectl rollout status deployment/grafana -n monitoring --timeout=120s

echo ""
echo "✓ Dashboard reloaded successfully!"
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward -n monitoring svc/grafana 3000:3000"
echo "  Then open: http://localhost:3000"

