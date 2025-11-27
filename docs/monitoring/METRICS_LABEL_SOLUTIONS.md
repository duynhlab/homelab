# Metrics App Label Solutions

## Overview

This document explains how the application metrics labels work and how they're configured in this project.

## Current Implementation

### How APP_NAME is Set

The application uses Kubernetes Downward API to automatically inject the `app` label from pod metadata into the `APP_NAME` environment variable.

**Helm Template** (`charts/templates/deployment.yaml`):

```yaml
containers:
  - name: {{ include "microservice.name" . }}
    env:
      - name: APP_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.labels['app']
      - name: NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
```

**Go Middleware** (`pkg/middleware/prometheus.go`):

```go
func getAppName() string {
    if name := os.Getenv("APP_NAME"); name != "" {
        return name
    }
    return "unknown"
}

func getNamespace() string {
    if ns := os.Getenv("NAMESPACE"); ns != "" {
        return ns
    }
    return "default"
}
```

### Benefits of This Approach

- **Automatic**: No hardcoded service names
- **Scalable**: New services automatically get correct labels
- **Consistent**: Labels come from Kubernetes pod metadata
- **Zero maintenance**: No need to update when adding services
- **Cloud-native**: Uses Kubernetes native features

## Metrics Labels

All custom metrics include these labels:

| Label | Source | Example |
|-------|--------|---------|
| `app` | `APP_NAME` env var (from pod label) | `auth` |
| `namespace` | `NAMESPACE` env var (from pod metadata) | `auth` |
| `method` | HTTP request method | `GET`, `POST` |
| `path` | Request path | `/api/v1/users` |
| `code` | HTTP status code | `200`, `404`, `500` |

## Custom Metrics

The 6 custom metrics defined in `pkg/middleware/prometheus.go`:

1. **`request_duration_seconds`** (Histogram)
   - Labels: `app`, `namespace`, `method`, `path`, `code`
   - Buckets: `0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10`

2. **`requests_total`** (Counter)
   - Labels: `app`, `namespace`, `method`, `path`, `code`

3. **`requests_in_flight`** (Gauge)
   - Labels: `app`, `namespace`, `method`, `path`

4. **`request_size_bytes`** (Histogram)
   - Labels: `app`, `namespace`, `method`, `path`, `code`

5. **`response_size_bytes`** (Histogram)
   - Labels: `app`, `namespace`, `method`, `path`, `code`

6. **`error_rate_total`** (Counter)
   - Labels: `app`, `namespace`, `method`, `path`, `code`

## Adding a New Service

When adding a new service, the labels are automatically configured through Helm:

1. Create values file (`charts/values/myapp.yaml`):

```yaml
name: myapp
namespace: myapp

image:
  repository: ghcr.io/duynhne
  name: myapp
  tag: latest
```

2. Deploy with Helm:

```bash
helm upgrade --install myapp charts/ \
  -f charts/values/myapp.yaml \
  -n myapp --create-namespace
```

The Helm chart automatically:
- Sets the `app` label on the pod
- Injects `APP_NAME` env var via Downward API
- Injects `NAMESPACE` env var via Downward API

## Verifying Labels

```bash
# Check pod labels
kubectl get pod -n auth -l app=auth -o jsonpath='{.items[0].metadata.labels}'

# Check env vars in pod
kubectl exec -n auth deployment/auth -- env | grep -E "(APP_NAME|NAMESPACE)"
# Output:
# APP_NAME=auth
# NAMESPACE=auth

# Check metrics labels
kubectl port-forward -n auth svc/auth 8080:8080
curl -s http://localhost:8080/metrics | grep request_duration_seconds | head -1
# Output: request_duration_seconds_bucket{app="auth",namespace="auth",method="GET",path="/health",code="200",le="0.005"} 10
```

## Troubleshooting

### Metrics Show `app="unknown"`

**Cause**: `APP_NAME` env var not set

**Solution**: Verify Helm deployment is correct:
```bash
helm get values auth -n auth
kubectl describe pod -n auth -l app=auth | grep -A5 "Environment:"
```

### Dashboard Shows No Data

**Cause**: Label mismatch between metrics and dashboard query

**Solution**: 
1. Check actual labels: `curl localhost:8080/metrics`
2. Check dashboard query uses correct filter: `app=~"$app"`
3. Verify Prometheus is scraping: http://localhost:9090/targets

## Related Documentation

- [METRICS.md](./METRICS.md) - Complete metrics documentation
- [ADDING_SERVICES.md](../getting-started/ADDING_SERVICES.md) - How to add new services
- [Helm Chart](../../charts/) - Chart templates and values
