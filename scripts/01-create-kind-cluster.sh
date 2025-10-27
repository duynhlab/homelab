#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Creating Kind Cluster ===${NC}"

# Check if Kind is installed
if ! command -v kind &> /dev/null; then
    echo -e "${YELLOW}Kind not found. Installing...${NC}"
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    echo -e "${GREEN}✓ Kind installed${NC}"
fi

# Delete existing cluster if exists
if kind get clusters | grep -q monitoring-local; then
    echo -e "${YELLOW}Deleting existing cluster...${NC}"
    kind delete cluster --name monitoring-local
fi

# Create cluster
echo -e "${GREEN}Creating Kind cluster with 3 nodes...${NC}"
kind create cluster --config kind/cluster-config.yaml

# Wait for cluster to be ready
echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# Verify cluster
echo ""
echo -e "${GREEN}=== Cluster Info ===${NC}"
kubectl cluster-info
echo ""
kubectl get nodes

echo ""
echo -e "${GREEN}✓ Kind cluster created successfully!${NC}"

