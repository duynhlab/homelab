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

# Service definitions: image-name:folder-name
# Image name is used for Docker tagging (matches Helm values)
# Folder name is the cmd/ directory name
SERVICES=(
    "auth:auth-service"
    "user:user-service"
    "product:product-service"
    "cart:cart-service"
    "order:order-service"
    "review:review-service"
    "notification:notification-service"
    "shipping:shipping-service"
    "shipping-v2:shipping-service-v2"
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

for entry in "${SERVICES[@]}"; do
    # Parse image-name:folder-name format
    IFS=':' read -r IMAGE_NAME FOLDER_NAME <<< "$entry"
    
    echo "Building $IMAGE_NAME (from cmd/$FOLDER_NAME)..."
    
    # Check if image already exists in Kind (skip only if not forcing rebuild)
    # Always rebuild if --no-cache or --force is specified
    if [ "$FORCE" != "true" ] && [ "$NO_CACHE" != "true" ] && check_image_in_kind $IMAGE_NAME; then
        echo "⚠️  $IMAGE_NAME image already exists in Kind, skipping build"
        echo "   Use --no-cache or --force to rebuild anyway"
        continue
    fi
    
    # If --no-cache or --force, always rebuild (skip check above)
    if [ "$NO_CACHE" = "true" ] || [ "$FORCE" = "true" ]; then
        echo "   Rebuilding $IMAGE_NAME (--no-cache flag detected)"
    fi
    
    # Build command with optional --no-cache flag
    # SERVICE_NAME uses folder name (for cmd/ path), image tag uses short name
    BUILD_CMD="docker build --build-arg SERVICE_NAME=$FOLDER_NAME -f services/Dockerfile -t $IMAGE_NAME:latest"
    if [ "$NO_CACHE" = "true" ]; then
        BUILD_CMD="$BUILD_CMD --no-cache"
        echo "   Building with --no-cache flag"
    fi
    BUILD_CMD="$BUILD_CMD services/"
    
    # Build with retry mechanism
    for attempt in 1 2 3; do
        if eval $BUILD_CMD; then
            echo "✅ $IMAGE_NAME built successfully"
            break
        else
            echo "⚠️  Build attempt $attempt failed, retrying..."
            if [ $attempt -eq 3 ]; then
                echo "❌ Failed to build $IMAGE_NAME after 3 attempts"
                exit 1
            fi
        fi
    done
    
    # Load to Kind with retry
    for attempt in 1 2 3; do
        if kind load docker-image $IMAGE_NAME:latest --name monitoring-local; then
            echo "✅ $IMAGE_NAME loaded to Kind"
            break
        else
            echo "⚠️  Load attempt $attempt failed, retrying..."
            if [ $attempt -eq 3 ]; then
                echo "❌ Failed to load $IMAGE_NAME to Kind after 3 attempts"
                exit 1
            fi
        fi
    done
    
    # Verify image is loaded in Kind
    if check_image_in_kind $IMAGE_NAME; then
        echo "✅ $IMAGE_NAME image verified in Kind cluster"
    else
        echo "❌ $IMAGE_NAME image not found in Kind cluster"
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