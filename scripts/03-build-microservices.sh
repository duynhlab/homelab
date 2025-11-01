#!/bin/bash
set -e

echo "=== Building All Microservices ==="

# Parse command line arguments
NO_CACHE="false"
FORCE="false"

if [ "$1" = "--no-cache" ] || [ "$1" = "--force" ]; then
    NO_CACHE="true"
fi

if [ "$1" = "--force" ]; then
    FORCE="true"
    NO_CACHE="true"
fi

SERVICES=(
    "auth-service"
    "user-service"
    "product-service"
    "cart-service"
    "order-service"
    "review-service"
    "notification-service"
    "shipping-service"
    "shipping-service-v2"
)

# Function to check if image exists in Kind cluster
check_image_in_kind() {
    local service=$1
    docker exec -it monitoring-local-control-plane crictl images 2>/dev/null | grep -q "library/$service" || return 1
}

# Function to wait for pods to be ready
wait_for_pods() {
    local namespace=$1
    local app_label=$2
    local timeout=${3:-60}
    
    echo "Waiting for $app_label pods in $namespace namespace..."
    kubectl wait --for=condition=ready pod -l app=$app_label -n $namespace --timeout=${timeout}s || {
        echo "❌ $app_label pods not ready after ${timeout}s"
        echo "Checking pod status:"
        kubectl get pods -n $namespace -l app=$app_label
        echo "Pod logs:"
        kubectl logs -n $namespace -l app=$app_label --tail=10
        return 1
    }
    echo "✅ $app_label pods are ready"
}

for service in "${SERVICES[@]}"; do
    echo "Building $service..."
    
    # Check if image already exists in Kind (skip only if not forcing rebuild)
    # Always rebuild if --no-cache or --force is specified
    if [ "$FORCE" != "true" ] && [ "$NO_CACHE" != "true" ] && check_image_in_kind $service; then
        echo "⚠️  $service image already exists in Kind, skipping build"
        echo "   Use --no-cache or --force to rebuild anyway"
        continue
    fi
    
    # If --no-cache or --force, always rebuild (skip check above)
    if [ "$NO_CACHE" = "true" ] || [ "$FORCE" = "true" ]; then
        echo "   Rebuilding $service (--no-cache flag detected)"
    fi
    
    # Build command with optional --no-cache flag
    BUILD_CMD="docker build --build-arg SERVICE_NAME=$service -f Dockerfile -t $service:latest"
    if [ "$NO_CACHE" = "true" ]; then
        BUILD_CMD="$BUILD_CMD --no-cache"
        echo "   Building with --no-cache flag"
    fi
    BUILD_CMD="$BUILD_CMD ."
    
    # Build with retry mechanism
    for attempt in 1 2 3; do
        if eval $BUILD_CMD; then
            echo "✅ $service built successfully"
            break
        else
            echo "⚠️  Build attempt $attempt failed, retrying..."
            if [ $attempt -eq 3 ]; then
                echo "❌ Failed to build $service after 3 attempts"
                exit 1
            fi
        fi
    done
    
    # Load to Kind with retry
    for attempt in 1 2 3; do
        if kind load docker-image $service:latest --name monitoring-local; then
            echo "✅ $service loaded to Kind"
            break
        else
            echo "⚠️  Load attempt $attempt failed, retrying..."
            if [ $attempt -eq 3 ]; then
                echo "❌ Failed to load $service to Kind after 3 attempts"
                exit 1
            fi
        fi
    done
    
    # Verify image is loaded in Kind
    if check_image_in_kind $service; then
        echo "✅ $service image verified in Kind cluster"
    else
        echo "❌ $service image not found in Kind cluster"
        exit 1
    fi
done

echo ""
echo "🎉 All 9 services built and loaded to Kind cluster!"
echo ""
echo "Usage:"
echo "  ./scripts/03-build-microservices.sh              # Normal build (use cache, skip existing)"
echo "  ./scripts/03-build-microservices.sh --no-cache   # Rebuild without cache"
echo "  ./scripts/03-build-microservices.sh --force      # Force rebuild all (no cache, skip checks)"