# APM Stack

## Overview

The APM (Application Performance Monitoring) stack includes:
- **Tempo**: Distributed tracing backend
- **Pyroscope**: Continuous profiling
- **Loki**: Log aggregation
- **Vector**: Log collection and routing
- **Jaeger**: Distributed tracing UI

## Installation Method

Currently installed via kubectl apply (transitioning to Kustomize in Phase 1):

```bash
# Tempo
kubectl apply -f k8s/tempo/

# Pyroscope  
kubectl apply -f k8s/pyroscope/

# Loki
kubectl apply -f k8s/loki/

# Vector
kubectl apply -f k8s/vector/

# Jaeger
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm upgrade --install jaeger jaegertracing/jaeger \
  --namespace apm \
  --create-namespace \
  --values k8s/jaeger/values.yaml
```

## Flux Integration

For Phase 1, we'll migrate kubectl manifests to Kustomize and use Flux HelmRelease for Jaeger.

## Files

See existing configurations:
- `k8s/tempo/`
- `k8s/pyroscope/`
- `k8s/loki/`
- `k8s/vector/`
- `k8s/jaeger/values.yaml`
