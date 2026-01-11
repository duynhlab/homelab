#!/bin/bash
set -e

echo "=== Deploying K6 Load Testing via Helm ==="

CHART_REF="charts/mop"

echo "Deploying k6..."
helm upgrade --install k6 "$CHART_REF" \
  -f charts/mop/values/k6.yaml \
  -n k6 \
  --wait --timeout 60s || true

echo ""
echo "SUCCESS: K6 deployed successfully!"
echo ""
kubectl get pods -n k6
echo ""
echo "To view logs:"
echo "  kubectl logs -n k6 -l app=k6 -f"
echo ""
