#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Installing Metrics Infrastructure (Helm) ==="

if ! command -v helm >/dev/null 2>&1; then
  echo "❌ Helm is required. Please install Helm v3+ and rerun this script."
  exit 1
fi

echo "Adding/Updating Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "1. Installing kube-state-metrics (Helm)..."
helm upgrade --install kube-state-metrics prometheus-community/kube-state-metrics \
  --namespace kube-system \
  -f "${ROOT_DIR}/k8s/metrics/kube-state-metrics-values.yaml"

echo "2. Installing metrics-server (Helm)..."
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  -f "${ROOT_DIR}/k8s/metrics/metrics-server-values.yaml"

echo "Waiting for kube-state-metrics..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kube-state-metrics -n kube-system --timeout=120s || true

echo "Waiting for metrics-server..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=metrics-server -n kube-system --timeout=120s || true

echo ""
echo "=== Metrics Infrastructure Status ==="
kubectl get pods -n kube-system | grep -E "(kube-state-metrics|metrics-server)" || true

echo ""
echo "✓ Metrics infrastructure installed successfully!"