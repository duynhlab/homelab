#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Cleaning Up Kind Cluster ===${NC}"
echo ""

# Ask for confirmation
# read -p "Are you sure you want to delete the Kind cluster? (y/N) " -n 1 -r
# echo
# if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#     echo -e "${BLUE}Cleanup cancelled.${NC}"
#     exit 0
# fi

# Delete Kind cluster
echo -e "${GREEN}Deleting Kind cluster...${NC}"
kind delete cluster --name monitoring-local

# Delete all namespaces
echo -e "${GREEN}Deleting all namespaces...${NC}"
kubectl delete namespace auth user product cart order review notification shipping monitoring --ignore-not-found=true

# Clean up Hey test results
echo -e "${GREEN}Cleaning up test results...${NC}"
rm -f /tmp/hey_*.txt

# Stop Docker Compose services if running
if [ -f "docker-compose.yml" ]; then
    echo -e "${GREEN}Stopping Docker Compose services...${NC}"
    docker compose down 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}✓ Cleanup complete!${NC}"
echo ""
echo -e "${BLUE}To redeploy:${NC}"
echo "  ./scripts/deploy-from-scratch.sh"
echo ""

