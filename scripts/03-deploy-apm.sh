#!/bin/bash

set -e

echo "Deploying all APM components..."

# Deploy Tempo
echo "Deploying Tempo..."
./scripts/03a-deploy-tempo.sh

# Deploy Pyroscope
echo "Deploying Pyroscope..."
./scripts/03b-deploy-pyroscope.sh

# Deploy Loki and Vector
echo "Deploying Loki and Vector..."
./scripts/03c-deploy-loki.sh

# Deploy Jaeger and OpenTelemetry Collector
echo "Deploying Jaeger and OpenTelemetry Collector..."
./scripts/03d-deploy-jaeger.sh

# Apply APM datasources to Grafana Operator
echo "Applying APM datasources to Grafana Operator..."
kubectl apply -f k8s/grafana-operator/datasource-tempo.yaml
kubectl apply -f k8s/grafana-operator/datasource-loki.yaml
kubectl apply -f k8s/grafana-operator/datasource-pyroscope.yaml

echo "Waiting for datasources to sync..."
sleep 5
kubectl get grafanadatasource -n monitoring

echo ""
echo "=========================================="
echo "APM Stack deployed successfully!"
echo "=========================================="
echo ""
echo "Components:"
echo "  - Tempo (Tracing): http://tempo.monitoring.svc.cluster.local:3200"
echo "  - Jaeger (Tracing): http://jaeger-all-in-one.monitoring.svc.cluster.local:16686"
echo "  - OTel Collector (Fan-out): http://otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318"
echo "  - Pyroscope (Profiling): http://pyroscope.monitoring.svc.cluster.local:4040"
echo "  - Loki (Logs): http://loki.monitoring.svc.cluster.local:3100"
echo "  - Vector (Log Collection): Running as DaemonSet"
echo ""
echo "Grafana datasources created via Grafana Operator:"
echo "  - Tempo (traces)"
echo "  - Jaeger (traces)"
echo "  - Pyroscope (profiles)"
echo "  - Loki (logs)"
echo ""
echo "Access Grafana to view APM dashboards:"
echo "  kubectl port-forward -n monitoring svc/grafana-service 3000:3000"
echo "  Then open http://localhost:3000"
echo ""
echo "Access Jaeger UI:"
echo "  kubectl port-forward -n monitoring svc/jaeger-all-in-one 16686:16686"
echo "  Then open http://localhost:16686"

