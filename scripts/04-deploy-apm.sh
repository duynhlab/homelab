#!/bin/bash

set -e

echo "Deploying all APM components..."

# Deploy Tempo
echo "Deploying Tempo..."
./scripts/04a-deploy-tempo.sh

# Deploy Pyroscope
echo "Deploying Pyroscope..."
./scripts/04b-deploy-pyroscope.sh

# Deploy Loki and Vector
echo "Deploying Loki and Vector..."
./scripts/04c-deploy-loki.sh

# Update Grafana datasources
echo "Updating Grafana datasources..."
kubectl apply -f k8s/grafana/configmap-datasources.yaml
kubectl rollout restart deployment/grafana -n monitoring

echo "Waiting for Grafana to restart..."
kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring

echo ""
echo "=========================================="
echo "APM Stack deployed successfully!"
echo "=========================================="
echo ""
echo "Components:"
echo "  - Tempo (Tracing): http://tempo.monitoring.svc.cluster.local:3200"
echo "  - Pyroscope (Profiling): http://pyroscope.monitoring.svc.cluster.local:4040"
echo "  - Loki (Logs): http://loki.monitoring.svc.cluster.local:3100"
echo "  - Vector (Log Collection): Running as DaemonSet"
echo ""
echo "Grafana datasources have been updated with:"
echo "  - Tempo (traces)"
echo "  - Pyroscope (profiles)"
echo "  - Loki (logs)"
echo ""
echo "Access Grafana to view APM dashboards:"
echo "  kubectl port-forward -n monitoring svc/grafana-service 3000:3000"
echo "  Then open http://localhost:3000"

