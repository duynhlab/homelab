#!/bin/bash
set -e

echo "Reloading Grafana Dashboards..."

# Delete and recreate to force update
kubectl delete configmap grafana-dashboard-main grafana-dashboard-tempo -n monitoring --ignore-not-found
kubectl delete grafanadashboard microservices-monitoring -n monitoring --ignore-not-found
kubectl apply -k k8s/grafana-operator/dashboards/
kubectl rollout restart deployment/grafana-deployment -n monitoring

echo "SUCCESS: Dashboards reloaded!"
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward -n monitoring svc/grafana-service 3000:3000"
echo "  Then open http://localhost:3000/d/microservices-monitoring-001/"
