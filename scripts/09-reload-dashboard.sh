#!/bin/bash
set -e

echo "=== Reloading Grafana Dashboards (Operator Managed) ==="

echo "1. Re-applying dashboard ConfigMap + GrafanaDashboard CRs..."
kubectl apply -k k8s/grafana-operator/dashboards/

echo "2. Triggering dashboard reconciliation..."
kubectl annotate grafanadashboard \
  -n monitoring \
  --overwrite \
  --all \
  reload-time=$(date +%s)

echo ""
echo "✓ Dashboards will be reconciled by the Grafana Operator."
echo "Check status:"
echo "  kubectl get grafanadashboards -n monitoring"
echo ""
echo "Access Grafana (operator managed):"
echo "  kubectl port-forward -n monitoring svc/grafana-service 3000:3000"
echo "  http://localhost:3000"

