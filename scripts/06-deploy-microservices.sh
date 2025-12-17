#!/bin/bash
set -e

# =============================================================================
# Deploy All Microservices using Helm
# =============================================================================
# Usage:
#   ./06-deploy-microservices.sh              # Local mode (default)
#   ./06-deploy-microservices.sh --local      # Local mode (explicit)
#   ./06-deploy-microservices.sh --registry   # From ghcr.io OCI registry
# =============================================================================

# Configuration
REGISTRY="oci://ghcr.io/duynhne/charts/microservice"
LOCAL_CHART="charts/"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Get chart version from Chart.yaml
CHART_VERSION=$(grep '^version:' "$PROJECT_ROOT/charts/Chart.yaml" | awk '{print $2}')

# Parse arguments
MODE="${1:---local}"

if [[ "$MODE" == "--registry" ]]; then
  CHART_REF="$REGISTRY"
  echo "=== Deploying All Microservices from OCI Registry ==="
  echo "Chart: $CHART_REF"
  echo "Version: $CHART_VERSION"
else
  CHART_REF="$PROJECT_ROOT/$LOCAL_CHART"
  echo "=== Deploying All Microservices from Local Chart ==="
  echo "Chart: $CHART_REF"
  echo "Version: $CHART_VERSION"
fi

echo ""

# Service definitions: release-name:namespace:values-file
SERVICES=(
  "auth:auth:auth"
  "user:user:user"
  "product:product:product"
  "cart:cart:cart"
  "order:order:order"
  "review:review:review"
  "notification:notification:notification"
  "shipping:shipping:shipping"
  "shipping-v2:shipping:shipping-v2"
)

# Deploy namespaces first
echo "1. Creating namespaces..."
kubectl apply -f "$PROJECT_ROOT/k8s/namespaces.yaml"
echo ""

# Deploy each service
COUNT=2
for entry in "${SERVICES[@]}"; do
  IFS=':' read -r SERVICE NAMESPACE VALUES <<< "$entry"
  
  echo "$COUNT. Deploying $SERVICE to $NAMESPACE namespace (chart v$CHART_VERSION)..."
  
  if [[ "$MODE" == "--registry" ]]; then
    # Registry mode: specify version explicitly
    helm upgrade --install "$SERVICE" "$CHART_REF" \
      --version "$CHART_VERSION" \
      -f "$PROJECT_ROOT/charts/values/${VALUES}.yaml" \
      -n "$NAMESPACE" \
      --create-namespace \
      --wait \
      --timeout 60s || true
  else
    # Local mode: no version flag needed
    helm upgrade --install "$SERVICE" "$CHART_REF" \
      -f "$PROJECT_ROOT/charts/values/${VALUES}.yaml" \
      -n "$NAMESPACE" \
      --create-namespace \
      --wait \
      --timeout 60s || true
  fi
  
  COUNT=$((COUNT + 1))
done

echo ""
echo "SUCCESS: All 9 services deployed!"

# Wait for pods to be ready
echo ""
echo "Waiting for pods to be ready..."
for entry in "${SERVICES[@]}"; do
  IFS=':' read -r SERVICE NAMESPACE VALUES <<< "$entry"
  kubectl wait --for=condition=ready pod -l app="$SERVICE" -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
done

echo ""
echo "Pod Status Summary:"
echo ""

NAMESPACES=("auth" "user" "product" "cart" "order" "review" "notification" "shipping")
for NS in "${NAMESPACES[@]}"; do
  echo "--- $NS namespace ---"
  kubectl get pods -n "$NS" 2>/dev/null || echo "No pods found"
  echo ""
done

echo "=== Deployment Complete ==="
echo ""
echo "To check Helm releases:"
echo "  helm list -A"
echo ""
echo "To uninstall a service:"
echo "  helm uninstall <service-name> -n <namespace>"
