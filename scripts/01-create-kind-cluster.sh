#!/bin/bash
set -e

echo "=== Creating Kind Cluster ==="

# Check if Kind is installed
if ! command -v kind &> /dev/null; then
    echo "Kind not found. Installing..."
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    echo "✓ Kind installed"
fi

# Delete existing cluster if exists
if kind get clusters | grep -q monitoring-local; then
    echo "Deleting existing cluster..."
    kind delete cluster --name monitoring-local
fi

# Create cluster
echo "Creating Kind cluster with 3 nodes..."
kind create cluster --config ./kind/cluster-config.yaml

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# Verify cluster
echo ""
echo "=== Cluster Info ==="
kubectl cluster-info
echo ""
kubectl get nodes

echo ""
echo "✓ Kind cluster created successfully!"

