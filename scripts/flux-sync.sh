#!/usr/bin/env bash

set -o errexit

echo "Syncing Flux system..."
flux reconcile kustomization flux-system --with-source

echo "Syncing controllers (operators)..."
flux reconcile kustomization controllers-local --with-source

echo "Syncing configs (instances)..."
flux reconcile kustomization configs-local --with-source

echo "Syncing apps (microservices)..."
flux reconcile kustomization apps-local --with-source

echo ""
echo "=== Kustomization Status ==="
flux get kustomizations

echo ""
echo "=== Apps Tree ==="
flux tree kustomization apps-local

echo ""
echo "✔ Cluster sync complete"
