#!/usr/bin/env bash

set -o errexit

echo "Starting cluster bootstrap"

# Install or upgrade Flux Operator via Helm (idempotent)
# helm upgrade --install will install if not present, or upgrade if it exists
echo "Installing/upgrading Flux Operator via Helm..."
helm upgrade --install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
    --namespace flux-system \
    --create-namespace \
    --wait

echo "Waiting for Flux Operator to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/flux-operator -n flux-system

echo "Applying FluxInstance CRD..."
kubectl apply -k ./kubernetes/clusters/local/flux-system/

echo "Waiting for Flux controllers to be ready..."
sleep 10
kubectl wait --for=condition=ready --timeout=300s pod -l app.kubernetes.io/part-of=flux -n flux-system 2>/dev/null || true

echo "✔ Flux Operator is ready"
echo ""
echo "Next steps:"
echo "  1. Push manifests: make flux-push"
echo "  2. Wait for reconciliation: make flux-sync"
echo "  3. Check status: make flux-status"
