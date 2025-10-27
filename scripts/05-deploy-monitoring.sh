#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Deploying Monitoring Stack ===${NC}"

# Deploy Prometheus (simple deployment)
echo -e "${GREEN}1. Deploying Prometheus...${NC}"
kubectl apply -f k8s/prometheus/

# Wait for Prometheus
echo -e "${YELLOW}Waiting for Prometheus to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s || true

# Create Grafana dashboard ConfigMap
echo -e "${GREEN}2. Creating Grafana dashboard ConfigMap...${NC}"
kubectl create configmap grafana-dashboard-json --from-file=grafana-dashboard.json -n monitoring --dry-run=client -o yaml | kubectl apply -f -

# Deploy Grafana
echo -e "${GREEN}3. Deploying Grafana...${NC}"
kubectl apply -f k8s/grafana/

# Wait for Grafana
echo -e "${YELLOW}Waiting for Grafana to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=120s || true

# Check status
echo ""
echo -e "${GREEN}=== Monitoring Stack Status ===${NC}"
kubectl get pods -n monitoring
kubectl get svc -n monitoring
kubectl get servicemonitor -n monitoring

echo ""
echo -e "${GREEN}✓ Monitoring stack deployed successfully!${NC}"
echo -e "${BLUE}Prometheus: http://localhost:9090${NC}"
echo -e "${BLUE}Grafana:    http://localhost:3000 (admin/admin)${NC}"

