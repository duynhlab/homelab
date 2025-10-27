#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Setting up Access ===${NC}"

# Kill existing port forwards
echo -e "${YELLOW}Stopping existing port forwards...${NC}"
pkill -f "kubectl port-forward" || true

# Wait a moment
sleep 2

# Start port forwards
echo -e "${GREEN}Starting port forwards...${NC}"

# Grafana
echo -e "${YELLOW}Starting Grafana port forward (3000)...${NC}"
kubectl port-forward -n monitoring svc/grafana 3000:3000 > /dev/null 2>&1 &

# Prometheus
echo -e "${YELLOW}Starting Prometheus port forward (9090)...${NC}"
kubectl port-forward -n monitoring svc/prometheus 9090:9090 > /dev/null 2>&1 &

# User Service
echo -e "${YELLOW}Starting User Service port forward (8081)...${NC}"
kubectl port-forward -n user svc/user-service 8081:8080 > /dev/null 2>&1 &

# Wait for port forwards to be ready
echo -e "${YELLOW}Waiting for port forwards to be ready...${NC}"
sleep 5

echo ""
echo -e "${GREEN}✅ Port forwarding setup complete!${NC}"
echo ""
echo -e "${BLUE}Access URLs:${NC}"
echo -e "📊 Grafana:    http://localhost:3000 (admin/admin)"
echo -e "📈 Prometheus: http://localhost:9090"
echo -e "🔧 User API:   http://localhost:8081/api/v1/users"
echo ""
echo -e "${YELLOW}To stop port forwarding: pkill -f 'kubectl port-forward'${NC}"
