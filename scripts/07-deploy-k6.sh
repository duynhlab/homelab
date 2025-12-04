#!/bin/bash
set -e

echo "=== Deploying K6 Load Testing via Helm ==="

CHART_REF="charts/"
DEPLOY_MODE="${1:-both}"

# Ensure k6 namespace exists
kubectl get namespace k6 >/dev/null 2>&1 || kubectl create namespace k6

if [ "$DEPLOY_MODE" = "legacy" ] || [ "$DEPLOY_MODE" = "both" ]; then
  echo "1. Deploying k6-legacy..."
  helm upgrade --install k6-legacy "$CHART_REF" \
    -f charts/values/k6-legacy.yaml \
    -n k6 \
    --create-namespace \
    --wait --timeout 60s || true
fi

if [ "$DEPLOY_MODE" = "scenarios" ] || [ "$DEPLOY_MODE" = "both" ]; then
  echo "2. Deploying k6-scenarios..."
  helm upgrade --install k6-scenarios "$CHART_REF" \
    -f charts/values/k6-scenarios.yaml \
    -n k6 \
    --create-namespace \
    --wait --timeout 60s || true
fi

echo ""
echo "✅ K6 deployed successfully!"
echo ""
kubectl get pods -n k6
echo ""
echo "To view logs:"
echo "  kubectl logs -n k6 -l app=k6-legacy -f"
echo "  kubectl logs -n k6 -l app=k6-scenarios -f"
echo ""
echo "Usage:"
echo "  ./scripts/07-deploy-k6.sh both       # Deploy both (default)"
echo "  ./scripts/07-deploy-k6.sh legacy     # Deploy only legacy"
echo "  ./scripts/07-deploy-k6.sh scenarios  # Deploy only scenarios"

