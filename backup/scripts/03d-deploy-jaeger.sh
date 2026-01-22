#!/bin/bash

set -e

echo "Deploying Jaeger + OpenTelemetry Collector..."

# Step 1: Add Helm repositories
echo "Adding Helm repositories..."
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts 2>/dev/null || true
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
helm repo update

# Step 2: Deploy Jaeger
echo "Deploying Jaeger v2..."
helm upgrade --install jaeger jaegertracing/jaeger \
    -n monitoring \
    -f k8s/jaeger/values.yaml \
    --wait \
    --timeout 300s

# Step 3: Wait for Jaeger to be ready
# Note: Jaeger v2 deployment name is "jaeger" (not "jaeger-all-in-one")
echo "Waiting for Jaeger to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/jaeger -n monitoring || \
    kubectl get pods -n monitoring -l app.kubernetes.io/name=jaeger

# Step 4: Deploy OpenTelemetry Collector
echo "Deploying OpenTelemetry Collector..."
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
    -n monitoring \
    -f k8s/otel-collector/values.yaml \
    --wait \
    --timeout 300s

# Step 5: Wait for OTel Collector to be ready
echo "Waiting for OpenTelemetry Collector to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/otel-collector-opentelemetry-collector -n monitoring || \
    kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector

# Step 6: Apply Grafana datasource
echo "Applying Grafana Jaeger datasource..."
kubectl apply -f k8s/grafana-operator/datasource-jaeger.yaml

# Step 7: Verify deployments
echo ""
echo "Verifying deployments..."
kubectl get pods -n monitoring | grep -E "(jaeger|otel-collector)"
kubectl get svc -n monitoring | grep -E "(jaeger|otel-collector)"

echo ""
echo "Jaeger + OTel Collector deployed successfully!"
echo ""
echo "Access Jaeger UI:"
echo "  kubectl port-forward -n monitoring svc/jaeger-query 16686:16686"
echo "  Then open http://localhost:16686"
echo ""
echo "OTel Collector endpoint for microservices:"
echo "  OTEL_COLLECTOR_ENDPOINT=otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318"
