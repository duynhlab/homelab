#!/bin/bash
set -e

echo "=== Setting up Access ==="

# Kill existing port forwards
echo "Stopping existing port forwards..."
pkill -f "kubectl port-forward" || true

# Wait a moment
sleep 2

# Start port forwards
echo "Starting port forwards..."

# Grafana (operator managed)
echo "Starting Grafana port forward (3000)..."
kubectl port-forward -n monitoring svc/grafana-service 3000:3000 > /dev/null 2>&1 &

# Prometheus
echo "Starting Prometheus port forward (9090)..."
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 > /dev/null 2>&1 &

# User Service
echo "Starting User Service port forward (8081)..."
kubectl port-forward -n user svc/user 8081:8080 > /dev/null 2>&1 &

# Wait for port forwards to be ready
echo "Waiting for port forwards to be ready..."
sleep 5

echo ""
echo "✅ Port forwarding setup complete!"
echo ""
echo "Access URLs:"
echo "📊 Grafana:    http://localhost:3000 (anonymous access enabled)"
echo "📈 Prometheus: http://localhost:9090"
echo "🔧 User API:   http://localhost:8081/api/v1/users"
echo ""
echo "To stop port forwarding: pkill -f 'kubectl port-forward'"
