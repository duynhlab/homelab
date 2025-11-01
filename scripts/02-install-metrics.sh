#!/bin/bash
set -e

echo "=== Installing Metrics Infrastructure ==="

# Install kube-state-metrics
echo "1. Installing kube-state-metrics..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/master/examples/standard/service-account.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/master/examples/standard/cluster-role.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/master/examples/standard/cluster-role-binding.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/master/examples/standard/deployment.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kube-state-metrics/master/examples/standard/service.yaml

# Install metrics-server
echo "2. Installing metrics-server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics-server for Kind (insecure TLS)
echo "Patching metrics-server for Kind..."
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Wait for kube-state-metrics
echo "Waiting for kube-state-metrics..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kube-state-metrics -n kube-system --timeout=120s || true

# Wait for metrics-server
echo "Waiting for metrics-server..."
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s || true

echo ""
echo "=== Metrics Infrastructure Status ==="
kubectl get pods -n kube-system | grep -E "(kube-state-metrics|metrics-server)"

echo ""
echo "✓ Metrics infrastructure installed successfully!"

