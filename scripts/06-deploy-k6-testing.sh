#!/bin/bash
set -e

echo "=== Deploying k6 Load Testing ==="

# Parse command line arguments
DEPLOY_MODE="${1:-both}"  # Options: legacy, multiple, both (default: both)

echo "Deploy mode: ${DEPLOY_MODE}"

# Create ConfigMap from both k6 load test scripts
echo "1. Creating k6 load test ConfigMap (both files)..."
kubectl create configmap k6-load-test \
  --from-file=k6/load-test.js \
  --from-file=k6/load-test-multiple-scenarios.js \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -

# Deploy k6 load generators based on mode
if [ "$DEPLOY_MODE" = "legacy" ] || [ "$DEPLOY_MODE" = "both" ]; then
  echo "2. Deploying k6 legacy load generator..."
  kubectl apply -f k8s/k6/deployment-legacy.yaml
fi

if [ "$DEPLOY_MODE" = "multiple" ] || [ "$DEPLOY_MODE" = "both" ]; then
  echo "3. Deploying k6 multiple-scenarios load generator..."
  kubectl apply -f k8s/k6/deployment-multiple-scenarios.yaml
fi

# Wait for k6 pods to be ready
echo "4. Waiting for k6 pods to be ready..."
if [ "$DEPLOY_MODE" = "legacy" ] || [ "$DEPLOY_MODE" = "both" ]; then
  kubectl wait --for=condition=ready pod -l app=k6-load-generator-legacy -n monitoring --timeout=120s || true
fi
if [ "$DEPLOY_MODE" = "multiple" ] || [ "$DEPLOY_MODE" = "both" ]; then
  kubectl wait --for=condition=ready pod -l app=k6-load-generator-scenarios -n monitoring --timeout=120s || true
fi

# Check k6 pod status
echo "5. Checking k6 pod status..."
kubectl get pods -n monitoring -l 'app in (k6-load-generator-legacy,k6-load-generator-scenarios)'

echo ""
echo "✅ k6 load testing deployed successfully!"
echo ""
if [ "$DEPLOY_MODE" = "both" ]; then
  echo "Both load generators are running:"
  echo "  - Legacy random testing (k6-load-generator-legacy)"
  echo "  - Multiple scenarios (k6-load-generator-scenarios)"
elif [ "$DEPLOY_MODE" = "legacy" ]; then
  echo "Legacy random testing is running"
elif [ "$DEPLOY_MODE" = "multiple" ]; then
  echo "Multiple scenarios testing is running"
fi
echo ""
echo "To view k6 logs:"
if [ "$DEPLOY_MODE" = "legacy" ] || [ "$DEPLOY_MODE" = "both" ]; then
  echo "  kubectl logs -n monitoring -l app=k6-load-generator-legacy -f"
fi
if [ "$DEPLOY_MODE" = "multiple" ] || [ "$DEPLOY_MODE" = "both" ]; then
  echo "  kubectl logs -n monitoring -l app=k6-load-generator-scenarios -f"
fi
echo ""
echo "To check load test progress:"
if [ "$DEPLOY_MODE" = "legacy" ] || [ "$DEPLOY_MODE" = "both" ]; then
  echo "  kubectl exec -n monitoring -l app=k6-load-generator-legacy -- ps aux"
fi
if [ "$DEPLOY_MODE" = "multiple" ] || [ "$DEPLOY_MODE" = "both" ]; then
  echo "  kubectl exec -n monitoring -l app=k6-load-generator-scenarios -- ps aux"
fi
echo ""
echo "Usage:"
echo "  ./scripts/06-deploy-k6-testing.sh both        # Deploy both (default)"
echo "  ./scripts/06-deploy-k6-testing.sh legacy      # Deploy only legacy"
echo "  ./scripts/06-deploy-k6-testing.sh multiple    # Deploy only multiple scenarios"
