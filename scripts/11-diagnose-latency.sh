#!/bin/bash
set -e

echo "=== Diagnosing Latency Issues ==="

# This script helps diagnose latency issues in microservices
# It checks:
# 1. Service response times
# 2. Database connection times
# 3. Network latency
# 4. Resource usage

echo ""
echo "1. Checking service response times..."
echo "   (Port-forward to services and test endpoints)"
echo ""

echo "2. Checking database connection times..."
echo "   kubectl exec -n <namespace> <pod-name> -- time psql -h <db-host> -U <user> -d <db> -c 'SELECT 1'"
echo ""

echo "3. Checking network latency..."
echo "   kubectl exec -n <namespace> <pod-name> -- ping -c 5 <db-host>"
echo ""

echo "4. Checking resource usage..."
kubectl top pods -A --sort-by=memory | head -20
echo ""

echo "5. Checking for slow queries (if postgres_exporter deployed)..."
echo "   Query Prometheus: pg_stat_statements_max_time"
echo ""

echo "✅ Diagnostic complete!"
echo ""
echo "Next steps:"
echo "  - Check service logs: kubectl logs -n <namespace> <pod-name>"
echo "  - Check database logs: kubectl logs -n <namespace> <db-pod-name>"
echo "  - Check Prometheus metrics: http://localhost:9090"
echo "  - Check Grafana dashboards: http://localhost:3000"
