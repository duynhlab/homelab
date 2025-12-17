#!/bin/bash
set -e

echo "=== Deploying K6 Load Testing via Helm ==="

CHART_REF="charts/"

# Ensure k6 namespace exists
kubectl get namespace k6 >/dev/null 2>&1 || kubectl create namespace k6

echo "Deploying k6-scenarios..."
helm upgrade --install k6-scenarios "$CHART_REF" \
  -f charts/values/k6-scenarios.yaml \
  -n k6 \
  --create-namespace \
  --wait --timeout 60s || true

echo ""
echo "✅ K6 deployed successfully!"
echo ""
kubectl get pods -n k6
echo ""
echo "To view logs:"
echo "  kubectl logs -n k6 -l app=k6-scenarios -f"
echo ""
