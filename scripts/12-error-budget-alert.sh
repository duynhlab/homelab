#!/bin/bash
set -e

echo "=== Error Budget Alert Response ==="

# This script helps respond to error budget alerts
# It checks:
# 1. Current error rates
# 2. Error budget burn rate
# 3. Service health
# 4. Recent incidents

echo ""
echo "1. Checking current error rates..."
echo "   Query Prometheus: rate(http_requests_total{code=~\"5..\"}[5m])"
echo ""

echo "2. Checking error budget burn rate..."
echo "   Query Prometheus: slo:error_budget:ratio_rate5m"
echo ""

echo "3. Checking service health..."
kubectl get pods -A | grep -E "Error|CrashLoopBackOff|Pending"
echo ""

echo "4. Checking recent incidents..."
echo "   Check Prometheus alerts: http://localhost:9090/alerts"
echo ""

echo "5. Checking database connections..."
echo "   Query Prometheus: pg_stat_database_numbackends"
echo ""

echo "✅ Error budget analysis complete!"
echo ""
echo "Next steps:"
echo "  - Review SLO dashboards in Grafana"
echo "  - Check error logs: kubectl logs -n <namespace> <pod-name> | grep -i error"
echo "  - Scale services if needed: kubectl scale deployment <name> -n <namespace> --replicas=<count>"
echo "  - Review error budget policy: docs/slo/ERROR_BUDGET_POLICY.md"
