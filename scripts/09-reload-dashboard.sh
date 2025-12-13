#!/bin/bash
set -e

echo "🔄 Reloading Grafana Dashboards..."

# Delete and recreate to force update
kubectl delete configmap grafana-dashboard-main grafana-dashboard-tempo -n monitoring --ignore-not-found
kubectl delete grafanadashboard microservices-monitoring -n monitoring --ignore-not-found
kubectl apply -k k8s/grafana-operator/dashboards/
kubectl rollout restart deployment/grafana-deployment -n monitoring
# Wait for reconciliation
sleep 5
echo "✅ Dashboard reloaded. Wait 30s for Grafana Operator to sync."
echo "   Access: http://localhost:3000 (clear cache if needed)"

