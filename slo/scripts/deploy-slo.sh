#!/bin/bash

# SLO Deployment Script
# Deploys all SLO components: rules, alerts, dashboards

set -e

NAMESPACE="monitoring-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🚀 Starting SLO deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

print_status "Connected to cluster: $(kubectl config current-context)"

# 1. Deploy SLO recording rules
print_status "Deploying SLO recording rules..."
kubectl apply -f "$PROJECT_ROOT/slo/k8s/error-budget-rules.yaml"
print_status "✅ SLO recording rules deployed"

# 2. Deploy SLO alerts
print_status "Deploying SLO alerts..."
kubectl apply -f "$PROJECT_ROOT/slo/k8s/slo-alerts.yaml"
print_status "✅ SLO alerts deployed"

# 3. Update Prometheus to load SLO rules
print_status "Updating Prometheus configuration..."
kubectl apply -f "$PROJECT_ROOT/k8s/prometheus/configmap.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/prometheus/deployment.yaml"
print_status "✅ Prometheus configuration updated"

# 4. Wait for Prometheus to restart
print_status "Waiting for Prometheus to restart..."
kubectl rollout status deployment/prometheus -n "$NAMESPACE" --timeout=300s
print_status "✅ Prometheus restarted successfully"

# 5. Deploy SLO dashboard
print_status "Deploying SLO dashboard..."
kubectl create configmap slo-dashboard-json \
    --from-file=slo-dashboard.json="$PROJECT_ROOT/slo/dashboards/slo-dashboard.json" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

# Update Grafana to load the new dashboard
kubectl apply -f "$PROJECT_ROOT/k8s/grafana/configmap-dashboards.yaml"
kubectl rollout restart deployment/grafana -n "$NAMESPACE"
print_status "✅ SLO dashboard deployed"

# 6. Wait for Grafana to restart
print_status "Waiting for Grafana to restart..."
kubectl rollout status deployment/grafana -n "$NAMESPACE" --timeout=300s
print_status "✅ Grafana restarted successfully"

# 7. Verify deployment
print_status "Verifying SLO deployment..."

# Check if SLO rules are loaded
print_status "Checking SLO recording rules..."
if kubectl get configmap prometheus-slo-rules -n "$NAMESPACE" &> /dev/null; then
    print_status "✅ SLO recording rules ConfigMap exists"
else
    print_warning "⚠️  SLO recording rules ConfigMap not found"
fi

# Check if SLO alerts are loaded
print_status "Checking SLO alerts..."
if kubectl get configmap prometheus-slo-alerts -n "$NAMESPACE" &> /dev/null; then
    print_status "✅ SLO alerts ConfigMap exists"
else
    print_warning "⚠️  SLO alerts ConfigMap not found"
fi

# Check if SLO dashboard is loaded
print_status "Checking SLO dashboard..."
if kubectl get configmap slo-dashboard-json -n "$NAMESPACE" &> /dev/null; then
    print_status "✅ SLO dashboard ConfigMap exists"
else
    print_warning "⚠️  SLO dashboard ConfigMap not found"
fi

# 8. Display access information
print_status "🎉 SLO deployment completed successfully!"
echo ""
echo "📊 Access your dashboards:"
echo "   Grafana:     kubectl port-forward -n $NAMESPACE svc/grafana 3000:3000"
echo "   Prometheus:  kubectl port-forward -n $NAMESPACE svc/prometheus 9090:9090"
echo ""
echo "🔗 Dashboard URLs:"
echo "   Main Dashboard:  http://localhost:3000/d/go-monitoring-demo/"
echo "   SLO Dashboard:   http://localhost:3000/d/slo-dashboard/"
echo ""
echo "📈 SLO Metrics to check in Prometheus:"
echo "   - slo:availability:success_rate_30d"
echo "   - slo:availability:error_budget_remaining_30d"
echo "   - slo:availability:burn_rate_1h"
echo "   - slo:availability:time_to_exhaustion_hours"
echo ""
echo "🚨 SLO Alerts to monitor:"
echo "   - SLOAvailabilityCritical"
echo "   - SLOAvailabilityWarning"
echo "   - SLOAvailabilityBudgetLow"
echo "   - SLOAvailabilityTimeToExhaustion"
echo ""
print_status "SLO deployment completed! 🎯"
