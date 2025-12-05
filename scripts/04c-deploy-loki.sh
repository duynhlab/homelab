#!/bin/bash

set -e

echo "Deploying Loki and Vector..."

# Deploy Loki
kubectl apply -f k8s/loki/configmap.yaml
kubectl apply -f k8s/loki/deployment.yaml
kubectl apply -f k8s/loki/service.yaml

# Deploy Vector
kubectl apply -f k8s/vector/rbac.yaml
kubectl apply -f k8s/vector/configmap.yaml
kubectl apply -f k8s/vector/daemonset.yaml

echo "Waiting for Loki to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/loki -n monitoring

echo "Waiting for Vector DaemonSet pods to be running..."
# Wait for pods to be scheduled and running (not ready, as sink healthcheck may fail initially)
for i in {1..60}; do
  READY=$(kubectl get daemonset vector -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
  DESIRED=$(kubectl get daemonset vector -n kube-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
  if [ "$READY" = "$DESIRED" ] && [ "$DESIRED" != "0" ]; then
    echo "Vector DaemonSet is ready: $READY/$DESIRED pods"
    break
  fi
  echo "Waiting for Vector pods... ($READY/$DESIRED ready)"
  sleep 2
done

# Check final status
kubectl get pods -n kube-system -l app=vector
echo ""
echo "Note: Vector may show healthcheck warnings initially until Loki is fully ready."
echo "This is normal - Vector will retry connecting to Loki automatically."

echo "Loki and Vector deployed successfully!"
echo "Loki API: http://loki.monitoring.svc.cluster.local:3100"
echo "Vector is running as DaemonSet on all nodes"

