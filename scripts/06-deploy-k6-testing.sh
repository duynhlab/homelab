#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Deploying k6 Load Testing ===${NC}"

# Create ConfigMap from k6 load test script
echo -e "${GREEN}1. Creating k6 load test ConfigMap...${NC}"
kubectl create configmap k6-load-test --from-file=k6/load-test.js -n monitoring --dry-run=client -o yaml | kubectl apply -f -

# Deploy k6 load generator
echo -e "${GREEN}2. Deploying k6 load generator...${NC}"
kubectl apply -f k8s/k6/

# Wait for k6 pod to be ready
echo -e "${YELLOW}3. Waiting for k6 pod to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=k6-load-generator -n monitoring --timeout=120s || true

# Check k6 pod status
echo -e "${GREEN}4. Checking k6 pod status...${NC}"
kubectl get pods -n monitoring -l app=k6-load-generator

echo ""
echo -e "${GREEN}✅ k6 load testing deployed successfully!${NC}"
echo -e "${BLUE}To view k6 logs:${NC}"
echo "  kubectl logs -n monitoring -l app=k6-load-generator -f"
echo ""
echo -e "${BLUE}To check load test progress:${NC}"
echo "  kubectl exec -n monitoring -l app=k6-load-generator -- ps aux"
