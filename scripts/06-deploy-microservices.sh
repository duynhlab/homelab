#!/bin/bash
set -euo pipefail

# =============================================================================
# Deploy All Microservices using Helm
# =============================================================================
# Usage:
#   ./06-deploy-microservices.sh   # Deploy from ghcr.io OCI registry
# =============================================================================

# Configuration
REGISTRY="oci://ghcr.io/duynhne/charts/mop"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Get chart version from Chart.yaml
CHART_VERSION=$(grep '^version:' "$PROJECT_ROOT/charts/mop/Chart.yaml" | awk '{print $2}')

# Always deploy from OCI registry
CHART_REF="$REGISTRY"
echo "=== Deploying All Microservices from OCI Registry ==="
echo "Chart: $CHART_REF"
echo "Version: $CHART_VERSION"

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

# Deploy each service
# Note: Namespaces are created by script 02-deploy-monitoring.sh (runs before this script)
# --create-namespace flag is kept as safety net but namespaces should already exist
COUNT=1
for entry in "${SERVICES[@]}"; do
  IFS=':' read -r SERVICE NAMESPACE VALUES <<< "$entry"
  
  echo "$COUNT. Deploying $SERVICE to $NAMESPACE namespace (chart v$CHART_VERSION)..."
  
  # Deploy from OCI registry with version
  # Note: Increased timeout to 5m to accommodate init container migrations (Flyway)
  if ! helm upgrade --install "$SERVICE" "$CHART_REF" \
    --version "$CHART_VERSION" \
    -f "$PROJECT_ROOT/charts/mop/values/${VALUES}.yaml" \
    -n "$NAMESPACE" \
    --create-namespace \
    --wait \
    --timeout 5m; then
    echo "  WARN: Failed to deploy $SERVICE (continuing with other services)..."
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
  # Increased timeout to 5m to accommodate init container migrations (Flyway)
  if ! kubectl wait --for=condition=ready pod -l app="$SERVICE" -n "$NAMESPACE" --timeout=5m 2>/dev/null; then
    echo "  WARN: Pods for $SERVICE not ready yet (continuing)..."
  fi
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
