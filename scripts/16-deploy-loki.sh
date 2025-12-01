#!/bin/bash

set -e

echo "Deploying Loki and Vector..."

# Deploy Loki
kubectl apply -f k8s/loki/configmap.yaml
kubectl apply -f k8s/loki/deployment.yaml
kubectl apply -f k8s/loki/service.yaml

# Deploy Vector
kubectl apply -f k8s/vector/rbac.yaml
kubectl apply -f k8s/vector/configmap.yaml
kubectl apply -f k8s/vector/daemonset.yaml

echo "Waiting for Loki to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/loki -n monitoring

echo "Waiting for Vector DaemonSet to be ready..."
kubectl wait --for=condition=ready --timeout=300s daemonset/vector -n monitoring

echo "Loki and Vector deployed successfully!"
echo "Loki API: http://loki.monitoring.svc.cluster.local:3100"
echo "Vector is running as DaemonSet on all nodes"

