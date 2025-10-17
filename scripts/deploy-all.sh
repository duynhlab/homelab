#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════╗"
echo "║   Complete Kind Deployment Script        ║"
echo "║   Go Monitoring Demo with Kubernetes     ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Step 1: Create Kind cluster
echo -e "${BLUE}Step 1/6: Creating Kind cluster...${NC}"
./scripts/01-create-kind-cluster.sh

# Step 2: Install metrics infrastructure
echo ""
echo -e "${BLUE}Step 2/6: Installing metrics infrastructure...${NC}"
./scripts/02-install-metrics-infrastructure.sh

# Step 3: Build and load image
echo ""
echo -e "${BLUE}Step 3/6: Building and loading application image...${NC}"
./scripts/03-build-and-load.sh

# Step 4: Deploy application
echo ""
echo -e "${BLUE}Step 4/6: Deploying Go application...${NC}"
./scripts/04-deploy-app.sh

# Step 5: Deploy monitoring
echo ""
echo -e "${BLUE}Step 5/6: Deploying monitoring stack...${NC}"
./scripts/05-deploy-monitoring.sh

# Step 6: Verify everything
echo ""
echo -e "${BLUE}Step 6/6: Verifying deployment...${NC}"
sleep 5

kubectl get pods -n monitoring-demo
kubectl get svc -n monitoring-demo

echo ""
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════╗"
echo "║   ✓ Deployment Complete!                 ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${BLUE}Services:${NC}"
echo "  - Go API:     http://localhost:8080"
echo "  - Prometheus: http://localhost:9090"
echo "  - Grafana:    http://localhost:3000"
echo ""
echo -e "${BLUE}Credentials:${NC}"
echo "  - Grafana: admin / admin"
echo ""
echo -e "${BLUE}Dashboard URL:${NC}"
echo "  http://localhost:3000/d/go-monitoring-demo/"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Open Grafana dashboard (auto-provisioned!)"
echo "  2. CronJob automatically generates traffic every 2 minutes"
echo "  3. Or manually trigger: kubectl create job --from=cronjob/demo-loadtest test-now -n monitoring-demo"
echo ""
echo -e "${GREEN}Ready to demo! 🚀${NC}"
echo ""

