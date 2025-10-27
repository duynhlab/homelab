#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Building All Microservices ===${NC}"

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
    
    echo -e "${YELLOW}Waiting for $app_label pods in $namespace namespace...${NC}"
    kubectl wait --for=condition=ready pod -l app=$app_label -n $namespace --timeout=${timeout}s || {
        echo -e "${RED}❌ $app_label pods not ready after ${timeout}s${NC}"
        echo -e "${YELLOW}Checking pod status:${NC}"
        kubectl get pods -n $namespace -l app=$app_label
        echo -e "${YELLOW}Pod logs:${NC}"
        kubectl logs -n $namespace -l app=$app_label --tail=10
        return 1
    }
    echo -e "${GREEN}✅ $app_label pods are ready${NC}"
}

for service in "${SERVICES[@]}"; do
    echo -e "${GREEN}Building $service...${NC}"
    
    # Check if image already exists in Kind
    if check_image_in_kind $service; then
        echo -e "${YELLOW}⚠️  $service image already exists in Kind, skipping build${NC}"
        continue
    fi
    
    # Build with retry mechanism
    for attempt in 1 2 3; do
        if docker build -f docker/$service.Dockerfile -t $service:latest .; then
            echo -e "${GREEN}✅ $service built successfully${NC}"
            break
        else
            echo -e "${YELLOW}⚠️  Build attempt $attempt failed, retrying...${NC}"
            if [ $attempt -eq 3 ]; then
                echo -e "${RED}❌ Failed to build $service after 3 attempts${NC}"
                exit 1
            fi
        fi
    done
    
    # Load to Kind with retry
    for attempt in 1 2 3; do
        if kind load docker-image $service:latest --name monitoring-local; then
            echo -e "${GREEN}✅ $service loaded to Kind${NC}"
            break
        else
            echo -e "${YELLOW}⚠️  Load attempt $attempt failed, retrying...${NC}"
            if [ $attempt -eq 3 ]; then
                echo -e "${RED}❌ Failed to load $service to Kind after 3 attempts${NC}"
                exit 1
            fi
        fi
    done
    
    # Verify image is loaded in Kind
    if check_image_in_kind $service; then
        echo -e "${GREEN}✅ $service image verified in Kind cluster${NC}"
    else
        echo -e "${RED}❌ $service image not found in Kind cluster${NC}"
        exit 1
    fi
done

echo ""
echo -e "${GREEN}🎉 All 9 services built and loaded to Kind cluster!${NC}"