#!/usr/bin/env bash

set -o errexit

echo "=== Setting up Access ==="
echo ""
echo "RECOMMENDED: Use /etc/hosts domain mapping instead of port-forwarding."
echo "See README.md for setup instructions."
echo ""
echo "This script provides fallback port-forwarding for environments"
echo "without /etc/hosts configuration or extraPortMappings."
echo ""

# Kill existing port forwards
echo "Stopping existing port forwards..."
pkill -f "kubectl port-forward" || true

# Wait a moment
sleep 2

# Start port forwards
echo "Starting port forwards..."

# Flux Web UI
echo "Starting Flux Web UI port forward (9080)..."
kubectl port-forward -n flux-system svc/flux-operator 9080:9080 > /dev/null 2>&1 &

# Grafana (operator managed)
echo "Starting Grafana port forward (3000)..."
kubectl port-forward -n monitoring svc/grafana-service 3000:3000 > /dev/null 2>&1 &

# VictoriaMetrics (VMSingle - Prometheus API compatible at :8428)
echo "Starting VictoriaMetrics port forward (8428)..."
kubectl port-forward -n monitoring svc/vmsingle-victoria-metrics 8428:8428 > /dev/null 2>&1 &

# VMAlert (alert rules + evaluation UI; also proxied under VMSingle /vmalert/)
echo "Starting VMAlert port forward (8080)..."
kubectl port-forward -n monitoring svc/vmalert-victoria-metrics 8080:8080 > /dev/null 2>&1 &

# Karma (Alertmanager alert dashboard — firing/silenced)
echo "Starting Karma port forward (8086 -> svc :8080)..."
kubectl port-forward -n monitoring svc/karma 8086:8080 > /dev/null 2>&1 &

# Jaeger
echo "Starting Jaeger port forward (16686)..."
kubectl port-forward -n monitoring svc/jaeger 16686:16686 > /dev/null 2>&1 &

# Tempo
echo "Starting Tempo port forward (3200)..."
kubectl port-forward -n monitoring svc/tempo 3200:3200 > /dev/null 2>&1 &

# Pyroscope
echo "Starting Pyroscope port forward (4040)..."
kubectl port-forward -n monitoring svc/pyroscope 4040:4040 > /dev/null 2>&1 &

# VictoriaLogs (Operator-managed VLSingle)
echo "Starting VictoriaLogs port forward (9428)..."
kubectl port-forward -n monitoring svc/vlsingle-victoria-logs 9428:9428 > /dev/null 2>&1 &

# RustFS (S3-compatible object storage)
echo "Starting RustFS port forward (9000 API, 9001 Console)..."
kubectl port-forward -n rustfs svc/rustfs-svc 9000:9000 9001:9001 > /dev/null 2>&1 &

# Postgres Operator UI
echo "Starting Postgres Operator UI port forward (8081)..."
kubectl port-forward -n postgres-operator svc/postgres-operator-ui 8081:80 > /dev/null 2>&1 &

# Kong API Gateway (HTTP + HTTPS)
echo "Starting Kong Gateway port forward (8000 HTTP, 8443 HTTPS)..."
kubectl port-forward -n kong svc/kong-kong-proxy 8000:80 8443:443 > /dev/null 2>&1 &

# Frontend (direct access, bypassing Kong)
echo "Starting Frontend port forward (3001)..."
kubectl port-forward -n default svc/frontend 3001:80 > /dev/null 2>&1 &

# Wait for port forwards to be ready
echo "Waiting for port forwards to be ready..."
sleep 5

echo ""
echo "SUCCESS: Port forwarding setup complete!"
echo ""
echo "Access URLs (port-forward fallback):"
echo "Flux Web UI:         http://localhost:9080"
echo "Grafana:             http://localhost:3000"
echo "VictoriaMetrics:     http://localhost:8428/vmui"
echo "VMAlert (rules):     http://localhost:8080"
echo "Karma (alerts):      http://localhost:8086"
echo "Jaeger:              http://localhost:16686"
echo "Tempo:               http://localhost:3200"
echo "Pyroscope:           http://localhost:4040"
echo "VictoriaLogs:        http://localhost:9428"
echo "RustFS Console:      http://localhost:9001 (API: 9000)"
echo "Postgres Operator UI: http://localhost:8081"
echo "Kong Gateway (HTTP):  http://gateway.duynhne.me:8000"
echo "Kong Gateway (HTTPS): https://gateway.duynhne.me:8443"
echo "Frontend (direct):   http://localhost:3001"
echo ""
echo "To stop port forwarding: pkill -f 'kubectl port-forward'"
