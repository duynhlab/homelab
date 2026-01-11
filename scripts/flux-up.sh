#!/usr/bin/env bash
# Copyright 2025 Stefan Prodan
# SPDX-License-Identifier: AGPL-3.0

set -o errexit

echo "Starting cluster bootstrap"

# Install Flux Operator via Helm (not flux-operator CLI)
echo "Installing Flux Operator via Helm..."
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
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

echo ""
echo "Waiting for infrastructure sync to complete"
kubectl wait --for=condition=ready --timeout=5m kustomization/infrastructure-local -n flux-system 2>/dev/null || true

echo "Waiting for monitoring sync to complete"
kubectl wait --for=condition=ready --timeout=5m kustomization/monitoring-local -n flux-system 2>/dev/null || true

echo "Waiting for apm sync to complete"
kubectl wait --for=condition=ready --timeout=5m kustomization/apm-local -n flux-system 2>/dev/null || true

echo "Waiting for databases sync to complete"
kubectl wait --for=condition=ready --timeout=10m kustomization/databases-local -n flux-system 2>/dev/null || true

echo "Waiting for apps sync to complete"
kubectl wait --for=condition=ready --timeout=5m kustomization/apps-local -n flux-system 2>/dev/null || true

echo "Waiting for slo sync to complete"
kubectl wait --for=condition=ready --timeout=5m kustomization/slo-local -n flux-system 2>/dev/null || true

echo "✔ Cluster is ready"
