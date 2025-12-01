#!/bin/bash

set -e

echo "Deploying Grafana Tempo..."

kubectl apply -f k8s/tempo/configmap.yaml
kubectl apply -f k8s/tempo/deployment.yaml
kubectl apply -f k8s/tempo/service.yaml

echo "Waiting for Tempo to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/tempo -n monitoring

echo "Tempo deployed successfully!"
echo "Tempo service: http://tempo.monitoring.svc.cluster.local:3200"
echo "OTLP HTTP endpoint: http://tempo.monitoring.svc.cluster.local:4318"
echo "OTLP gRPC endpoint: http://tempo.monitoring.svc.cluster.local:4317"

