#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Installing Metrics Infrastructure ===${NC}"

# Install kube-state-metrics
echo -e "${GREEN}1. Installing kube-state-metrics...${NC}"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/master/examples/standard/service-account.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/master/examples/standard/cluster-role.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/master/examples/standard/cluster-role-binding.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/master/examples/standard/deployment.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/master/examples/standard/service.yaml

# Install metrics-server
echo -e "${GREEN}2. Installing metrics-server...${NC}"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics-server for Kind (insecure TLS)
echo -e "${YELLOW}Patching metrics-server for Kind...${NC}"
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Wait for kube-state-metrics
echo -e "${YELLOW}Waiting for kube-state-metrics...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kube-state-metrics -n kube-system --timeout=120s || true

# Wait for metrics-server
echo -e "${YELLOW}Waiting for metrics-server...${NC}"
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s || true

echo ""
echo -e "${GREEN}=== Metrics Infrastructure Status ===${NC}"
kubectl get pods -n kube-system | grep -E "(kube-state-metrics|metrics-server)"

echo ""
echo -e "${GREEN}✓ Metrics infrastructure installed successfully!${NC}"

