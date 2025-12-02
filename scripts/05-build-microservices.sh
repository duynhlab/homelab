#!/bin/bash
set -e

echo "=== Building All Microservices ==="

# Registry configuration (must match Helm values)
REGISTRY="ghcr.io/duynhne"

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

# Service names (used for both image tagging and folder names)
SERVICES=(
    "auth"
    "user"
    "product"
    "cart"
    "order"
    "review"
    "notification"
    "shipping"
    "shipping-v2"
)

# Function to check if image exists in Kind cluster
check_image_in_kind() {
    local image=$1
    docker exec -it monitoring-local-control-plane crictl images 2>/dev/null | grep -q "$image" || return 1
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

for SERVICE in "${SERVICES[@]}"; do
    # Full image path (matches Helm values: ghcr.io/duynhne/<name>:v5)
    FULL_IMAGE="$REGISTRY/$SERVICE:v5"
    
    echo "Building $FULL_IMAGE (from cmd/$SERVICE)..."
    
    # Check if image already exists in Kind (skip only if not forcing rebuild)
    # Always rebuild if --no-cache or --force is specified
    if [ "$FORCE" != "true" ] && [ "$NO_CACHE" != "true" ] && check_image_in_kind "$REGISTRY/$SERVICE"; then
        echo "⚠️  $FULL_IMAGE already exists in Kind, skipping build"
        echo "   Use --no-cache or --force to rebuild anyway"
        continue
    fi
    
    # If --no-cache or --force, always rebuild (skip check above)
    if [ "$NO_CACHE" = "true" ] || [ "$FORCE" = "true" ]; then
        echo "   Rebuilding $FULL_IMAGE (--no-cache flag detected)"
    fi
    
    # Build command with optional --no-cache flag
    BUILD_CMD="docker build --build-arg SERVICE_NAME=$SERVICE -f services/Dockerfile -t $FULL_IMAGE"
    if [ "$NO_CACHE" = "true" ]; then
        BUILD_CMD="$BUILD_CMD --no-cache"
        echo "   Building with --no-cache flag"
    fi
    BUILD_CMD="$BUILD_CMD services/"
    
    # Build with retry mechanism
    for attempt in 1 2 3; do
        if eval $BUILD_CMD; then
            echo "✅ $FULL_IMAGE built successfully"
            break
        else
            echo "⚠️  Build attempt $attempt failed, retrying..."
            if [ $attempt -eq 3 ]; then
                echo "❌ Failed to build $FULL_IMAGE after 3 attempts"
                exit 1
            fi
        fi
    done
    
    # Load to Kind with retry
    for attempt in 1 2 3; do
        if kind load docker-image $FULL_IMAGE --name monitoring-local; then
            echo "✅ $FULL_IMAGE loaded to Kind"
            break
        else
            echo "⚠️  Load attempt $attempt failed, retrying..."
            if [ $attempt -eq 3 ]; then
                echo "❌ Failed to load $FULL_IMAGE to Kind after 3 attempts"
                exit 1
            fi
        fi
    done
    
    # Verify image is loaded in Kind
    if check_image_in_kind "$REGISTRY/$SERVICE"; then
        echo "✅ $FULL_IMAGE verified in Kind cluster"
    else
        echo "❌ $FULL_IMAGE not found in Kind cluster"
        exit 1
    fi
done

echo ""
echo "🎉 All 9 services built and loaded to Kind cluster!"
echo ""
echo "Usage:"
echo "  ./scripts/05-build-microservices.sh              # Normal build (use cache, skip existing)"
echo "  ./scripts/05-build-microservices.sh --no-cache   # Rebuild without cache"
echo "  ./scripts/05-build-microservices.sh --force      # Force rebuild all (no cache, skip checks)"