#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Deploying Go Application ===${NC}"

# Create namespace
echo -e "${GREEN}1. Creating namespace...${NC}"
kubectl apply -f k8s/namespace.yaml

# Deploy Go app
echo -e "${GREEN}2. Deploying Go application...${NC}"
kubectl apply -f k8s/go-app/

# Wait for pods
echo -e "${YELLOW}Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=demo-go-api -n monitoring-demo --timeout=120s

# Check deployment
echo ""
echo -e "${GREEN}=== Application Status ===${NC}"
kubectl get pods -n monitoring-demo -l app=demo-go-api
kubectl get svc -n monitoring-demo

echo ""
echo -e "${GREEN}✓ Application deployed successfully!${NC}"
echo -e "${BLUE}API accessible at: http://localhost:8080${NC}"

