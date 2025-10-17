#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Building and Loading Docker Image ===${NC}"

# Build Docker image
echo -e "${GREEN}1. Building Docker image...${NC}"
docker build -t demo-go-api:local .

# Load image into Kind cluster
echo -e "${GREEN}2. Loading image into Kind cluster...${NC}"
kind load docker-image demo-go-api:local --name monitoring-demo

# Verify image loaded
echo ""
echo -e "${GREEN}=== Verifying Image in Kind ===${NC}"
docker exec -it monitoring-demo-control-plane crictl images | grep demo-go-api || echo "Image loaded"

echo ""
echo -e "${GREEN}✓ Image built and loaded successfully!${NC}"

