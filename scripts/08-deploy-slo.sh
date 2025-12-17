#!/bin/bash
set -e

echo "=== Deploying Sloth SLO System ==="

NAMESPACE="monitoring"

# 1. Add Sloth Helm repo
echo "1. Adding Sloth Helm repository..."
helm repo add sloth https://slok.github.io/sloth >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

# 2. Deploy Sloth Operator
echo "2. Deploying Sloth Operator..."
helm upgrade --install sloth sloth/sloth \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f k8s/sloth/values.yaml \
  --wait --timeout 120s

# 3. Wait for operator
echo "3. Waiting for Sloth Operator..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=sloth -n "$NAMESPACE" --timeout=120s || true

# 4. Deploy PrometheusServiceLevel CRDs
echo "4. Deploying SLO definitions (PrometheusServiceLevel CRs)..."
kubectl apply -f k8s/sloth/crds/

# 5. Verify deployment
echo ""
echo "=== SLO System Status ==="
echo ""
echo "Sloth Operator:"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=sloth

echo ""
echo "PrometheusServiceLevel CRs:"
kubectl get prometheusservicelevels -n "$NAMESPACE"

echo ""
echo "Generated PrometheusRules:"
kubectl get prometheusrules -n "$NAMESPACE" | grep sloth || echo "  (Sloth will generate rules within a few seconds)"

echo ""
echo "Grafana Dashboards (SLO):"
kubectl get grafanadashboard -n "$NAMESPACE" | grep slo

echo ""
echo "SUCCESS: Sloth SLO system deployed successfully!"
echo ""
echo "Access:"
echo "  Grafana: kubectl port-forward -n $NAMESPACE svc/grafana-service 3000:3000"
echo "  URL: http://localhost:3000/dashboards (folder: SLO)"
echo ""
echo "  Prometheus: kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-prometheus 9090:9090"
echo "  Rules: http://localhost:9090/api/v1/rules"
echo "  Alerts: http://localhost:9090/alerts"
echo ""
echo "Verify SLO metrics:"
echo "  # Check SLO metrics"
echo "  kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-prometheus 9090:9090"
echo "  curl 'http://localhost:9090/api/v1/query?query=slo:sli_error:ratio_rate5m'"
echo ""
echo "Next steps:"
echo "  - View SLO dashboards in Grafana (IDs: 14348, 14643)"
echo "  - Check Prometheus rules and alerts"
echo "  - Monitor error budgets and burn rates"
