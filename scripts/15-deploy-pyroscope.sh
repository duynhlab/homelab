#!/bin/bash

set -e

echo "Deploying Pyroscope..."

kubectl apply -f k8s/pyroscope/configmap.yaml
kubectl apply -f k8s/pyroscope/deployment.yaml
kubectl apply -f k8s/pyroscope/service.yaml

echo "Waiting for Pyroscope to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/pyroscope -n monitoring

echo "Pyroscope deployed successfully!"
echo "Pyroscope UI: http://pyroscope.monitoring.svc.cluster.local:4040"

