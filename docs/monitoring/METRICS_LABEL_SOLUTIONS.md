# Metrics Label Architecture (Prometheus Operator)

## Quick Summary

**Objectives:**
- Understand how Prometheus automatically injects labels during scrape
- Learn ServiceMonitor-based auto-discovery for microservices
- Configure namespace-based service discovery at scale

**Learning Outcomes:**
- Label injection strategy: application vs Prometheus-added labels
- ServiceMonitor configuration for automatic pod discovery
- Namespace-based filtering with `monitoring: enabled`
- Troubleshooting label and discovery issues

**Keywords:**
Prometheus Operator, ServiceMonitor, Label Injection, Relabel Configs, Auto-discovery, Namespace Selector, Service Identification

**Technologies:**
- Prometheus Operator (v0.5.0+)
- ServiceMonitor CRD
- Kubernetes (namespace labels)
- Prometheus (relabel_configs)

## Overview

**Since v0.5.0**, this project uses **Prometheus Operator** with **ServiceMonitor-based auto-discovery**. Labels (`app`, `namespace`) are **automatically injected by Prometheus** during scrape, not by the application code.

**Consistent approach across the stack:**
- **Metrics (Prometheus)**: Labels auto-injected by Prometheus during scrape
- **Tracing (OpenTelemetry)**: Service name auto-detected from Kubernetes environment
- **Profiling (Pyroscope)**: Service name auto-detected from Kubernetes environment
- **No manual env var injection needed!**

**Key Changes from v0.4.x:**
- ❌ **Removed**: Downward API injection of `APP_NAME`, `NAMESPACE` env vars (for metrics and APM)
- ❌ **Removed**: `getAppName()`, `getNamespace()` functions in Go middleware
- ✅ **Added**: Single ServiceMonitor for all microservices
- ✅ **Added**: Prometheus relabel_configs auto-inject `app`, `namespace`
- ✅ **Added**: OpenTelemetry resource auto-detection for tracing/profiling

---

## Label Injection Strategy

### Application Level (Go Middleware)

Applications **only emit** 3 labels:

```go
// services/pkg/middleware/prometheus.go
var (
    requestDuration = promauto.NewHistogramVec(
        prometheus.HistogramOpts{
            Name: "request_duration_seconds",
            Help: "Duration of HTTP requests in seconds",
        },
        []string{"method", "path", "code"}, // ← Only 3 labels
    )
    // ... other metrics with same 3 labels
)
```

**Emitted labels:**
- `method` - HTTP method (GET, POST, PUT, DELETE)
- `path` - Request path (e.g., `/api/v1/users`)
- `code` - HTTP status code (200, 404, 500)

### Prometheus Level (Scrape Time)

Prometheus **automatically adds** 4 labels during scrape via ServiceMonitor relabel_configs:

- `app` - From pod's `metadata.labels.app`
- `namespace` - From pod's `metadata.namespace`
- `job` - From ServiceMonitor's job name (e.g., `microservices-api`)
- `instance` - Pod IP:port (e.g., `10.244.1.5:8080`)

### Final Metric Labels

After Prometheus scrape, metrics have **7 labels total**:

```promql
request_duration_seconds_bucket{
  app="auth",           # ← Added by Prometheus
  namespace="auth",     # ← Added by Prometheus
  job="microservices-api", # ← Added by Prometheus
  instance="10.244.1.5:8080", # ← Added by Prometheus
  method="GET",         # ← From application
  path="/api/v1/login", # ← From application
  code="200",           # ← From application
  le="0.1"
} 150
```

### Benefits of This Approach

1. **Eliminates Label Duplication**
   - Application doesn't need to know its own name or namespace
   - Prometheus is the source of truth for pod metadata

2. **Simplifies Application Code**
   - No env var injection needed
   - No helper functions to read pod metadata
   - Less code to maintain

3. **Follows Best Practices**
   - Prometheus Community best practice: let Prometheus add target labels
   - Aligns with Prometheus Operator patterns

4. **Scales to 1000+ Pods**
   - Single ServiceMonitor discovers all microservices
   - No manual scrape config per service
   - Automatic discovery as services scale

---

## ServiceMonitor-Based Auto-Discovery

### ServiceMonitor Configuration

**Single ServiceMonitor** for all microservices:

```yaml
# k8s/prometheus/servicemonitor-microservices.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: microservices-api
  namespace: monitoring
  labels:
    release: prometheus-operator
spec:
  namespaceSelector:
    matchLabels:
      monitoring: enabled  # ← Discovers services in labeled namespaces
  selector:
    matchLabels:
      app: "*"  # ← Matches all services with 'app' label
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
```

### How It Works

1. **Namespace Labeling**: Mark namespaces for discovery
   ```bash
   kubectl label namespace auth monitoring=enabled
   kubectl label namespace user monitoring=enabled
   # ... repeat for all service namespaces
   ```

2. **Pod Discovery**: ServiceMonitor automatically finds:
   - All pods in labeled namespaces
   - That have a service with `app` label
   - With a port named `http`

3. **Label Injection**: Prometheus adds `app`, `namespace` labels from pod metadata

4. **Scraping**: Prometheus scrapes `/metrics` endpoint every 15s

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Prometheus Operator                                         │
│                                                             │
│  ┌──────────────────┐       ┌──────────────────┐          │
│  │ ServiceMonitor   │──────▶│ Prometheus       │          │
│  │ (monitoring ns)  │       │ (scrape config)  │          │
│  └──────────────────┘       └──────────────────┘          │
│         │                            │                     │
└─────────┼────────────────────────────┼─────────────────────┘
          │                            │
          │ Discovers pods             │ Scrapes /metrics
          │ in labeled namespaces      │ + injects labels
          ▼                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Service Namespaces (labeled: monitoring=enabled)            │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ auth:8080    │  │ user:8080    │  │ product:8080 │     │
│  │ /metrics     │  │ /metrics     │  │ /metrics     │     │
│  │ (app=auth)   │  │ (app=user)   │  │ (app=product)│     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Metrics Labels Reference

### Label Source Table

| Label | Source | Example | Added By |
|-------|--------|---------|----------|
| `method` | HTTP request | `GET`, `POST` | Application |
| `path` | Request path | `/api/v1/users` | Application |
| `code` | Status code | `200`, `404`, `500` | Application |
| `app` | Pod label | `auth`, `user` | **Prometheus** |
| `namespace` | Pod namespace | `auth`, `user` | **Prometheus** |
| `job` | ServiceMonitor | `microservices-api` | **Prometheus** |
| `instance` | Pod IP:port | `10.244.1.5:8080` | **Prometheus** |

### Custom Metrics (6 Total)

All 6 custom metrics use the same **3 application-level labels** (`method`, `path`, `code`):

1. **`request_duration_seconds`** (Histogram)
   - Labels: `method`, `path`, `code`
   - Buckets: `0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10`

2. **`requests_total`** (Counter)
   - Labels: `method`, `path`, `code`

3. **`requests_in_flight`** (Gauge)
   - Labels: `method`, `path` (no `code` - requests not completed yet)

4. **`request_size_bytes`** (Histogram)
   - Labels: `method`, `path`, `code`

5. **`response_size_bytes`** (Histogram)
   - Labels: `method`, `path`, `code`

6. **`error_rate_total`** (Counter)
   - Labels: `method`, `path`, `code`

**Note**: Prometheus automatically adds `app`, `namespace`, `job`, `instance` to all metrics during scrape.

---

## Adding a New Service

### Step-by-Step Guide

1. **Create Helm values file** (`charts/values/myapp.yaml`):

```yaml
name: myapp
namespace: myapp

image:
  repository: ghcr.io/duynhne
  name: myapp
  tag: latest

replicaCount: 2

service:
  type: ClusterIP
  port: 8080
  targetPort: 8080
  portName: http  # ← Required for ServiceMonitor
```

2. **Label the namespace** for discovery:

```bash
kubectl create namespace myapp
kubectl label namespace myapp monitoring=enabled
```

3. **Deploy with Helm**:

```bash
helm upgrade --install myapp charts/ \
  -f charts/values/myapp.yaml \
  -n myapp
```

4. **Verify discovery**:

```bash
# Check ServiceMonitor discovered the new service
kubectl get servicemonitor -n monitoring
kubectl describe servicemonitor microservices-api -n monitoring

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open: http://localhost:9090/targets
# Look for: myapp/myapp/0 (1/1 up)
```

### What Happens Automatically

- ✅ Helm creates pod with `app: myapp` label
- ✅ ServiceMonitor discovers pod (namespace has `monitoring: enabled`)
- ✅ Prometheus scrapes `/metrics` endpoint
- ✅ Prometheus injects `app="myapp"`, `namespace="myapp"` labels
- ✅ Metrics appear in Grafana dashboard (select "myapp" from `$app` dropdown)

### No Manual Configuration Needed

- ❌ No env var injection
- ❌ No Prometheus ConfigMap updates
- ❌ No scrape config changes
- ❌ No pod restarts

---

## Verifying Labels

### 1. Check ServiceMonitor

```bash
kubectl get servicemonitor -n monitoring
# NAME                  AGE
# microservices-api     2d

kubectl describe servicemonitor microservices-api -n monitoring
# Should show:
# - namespaceSelector: monitoring=enabled
# - selector: app=*
```

### 2. Check Namespace Labels

```bash
kubectl get namespaces --show-labels | grep monitoring=enabled
# auth        Active   2d   monitoring=enabled
# user        Active   2d   monitoring=enabled
# product     Active   2d   monitoring=enabled
# ...
```

### 3. Check Prometheus Targets

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

Open: http://localhost:9090/targets

Look for targets like:
```
serviceMonitor/monitoring/microservices-api/0
  auth/auth/0 (1/1 up)
  user/user/0 (1/1 up)
  product/product/0 (1/1 up)
  ...
```

### 4. Check Raw Metrics

```bash
kubectl port-forward -n auth svc/auth 8080:8080
curl -s http://localhost:8080/metrics | grep request_duration_seconds_count | head -1
```

**Before Prometheus scrape** (raw from app):
```promql
request_duration_seconds_count{method="GET",path="/health",code="200"} 150
```

**After Prometheus scrape** (in Prometheus):
```promql
request_duration_seconds_count{
  app="auth",
  namespace="auth",
  job="microservices-api",
  instance="10.244.1.5:8080",
  method="GET",
  path="/health",
  code="200"
} 150
```

### 5. Check in Grafana

```bash
kubectl port-forward -n monitoring svc/grafana-service 3000:3000
```

Open: http://localhost:3000/d/microservices-monitoring-001/

1. Select service from `$app` dropdown
2. Check panels show data
3. Run query in Explore:
   ```promql
   request_duration_seconds_count{app="auth"}
   ```

---

## Troubleshooting

### Issue: ServiceMonitor Not Finding Pods

**Symptoms:**
- No targets in Prometheus UI
- Dashboard shows "No data"

**Diagnosis:**
```bash
# 1. Check namespace has label
kubectl get namespace auth -o jsonpath='{.metadata.labels.monitoring}'
# Should output: enabled

# 2. Check pod has app label
kubectl get pods -n auth -o jsonpath='{.items[0].metadata.labels.app}'
# Should output: auth

# 3. Check service exists with app label
kubectl get svc -n auth -l app=auth
# Should show auth service

# 4. Check service has 'http' port
kubectl get svc auth -n auth -o jsonpath='{.spec.ports[*].name}'
# Should include: http
```

**Solutions:**
```bash
# Add namespace label
kubectl label namespace auth monitoring=enabled --overwrite

# Verify Helm deployed with correct labels
helm get values auth -n auth

# Restart Prometheus Operator to re-sync
kubectl rollout restart deployment -n monitoring prometheus-operator-kube-prom-operator
```

### Issue: Metrics Missing `app` or `namespace` Labels

**Symptoms:**
- Metrics show in Prometheus but missing `app` label
- Dashboard queries fail with "no data"

**Diagnosis:**
```bash
# Check Prometheus relabel configs
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Open: http://localhost:9090/config
# Search for: relabel_configs
```

**Solutions:**
1. Verify ServiceMonitor has correct labels:
   ```bash
   kubectl get servicemonitor microservices-api -n monitoring -o yaml
   ```

2. Check Prometheus Operator logs:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=kube-prometheus-stack-operator
   ```

3. Recreate ServiceMonitor:
   ```bash
   kubectl delete servicemonitor microservices-api -n monitoring
   kubectl apply -f k8s/prometheus/servicemonitor-microservices.yaml
   ```

### Issue: Dashboard Shows No Data

**Symptoms:**
- Prometheus has data
- Grafana dashboard is empty

**Diagnosis:**
```bash
# 1. Check Grafana datasource
# Open: http://localhost:3000/datasources
# Test Prometheus datasource

# 2. Run query in Grafana Explore
# Query: request_duration_seconds_count{app="auth"}

# 3. Check dashboard variable
# Dashboard Settings → Variables → $app
# Should show: auth, user, product, etc.
```

**Solutions:**
1. Verify dashboard queries use correct labels:
   ```promql
   # Should have: app=~"$app", namespace=~"$namespace"
   sum(rate(request_duration_seconds_count{app=~"$app",namespace=~"$namespace"}[5m]))
   ```

2. Check time range (top-right dropdown) includes recent data

3. Reload dashboard:
   ```bash
   ./scripts/10-reload-dashboard.sh
   ```

### Issue: High Cardinality Warning

**Symptoms:**
- Prometheus slow
- Warning: "high cardinality metrics"

**Cause:**
Too many unique label combinations (e.g., unique `path` values)

**Solutions:**
1. **Aggregate high-cardinality labels** in queries:
   ```promql
   # Instead of showing all paths
   sum by (app) (rate(requests_total[5m]))
   
   # Or limit to top 10
   topk(10, sum by (path) (rate(requests_total[5m])))
   ```

2. **Use relabeling** to drop/aggregate labels in ServiceMonitor:
   ```yaml
   # k8s/prometheus/servicemonitor-microservices.yaml
   endpoints:
   - port: http
     path: /metrics
     relabelings:
     - sourceLabels: [__meta_kubernetes_pod_label_version]
       action: drop  # Don't scrape version label
   ```

---

## Related Documentation

- [METRICS.md](./METRICS.md) - Complete metrics documentation
- [PROMETHEUS_RATE_EXPLAINED.md](./PROMETHEUS_RATE_EXPLAINED.md) - rate() and increase() functions
- [VARIABLES_REGEX.md](./VARIABLES_REGEX.md) - Dashboard variables and filtering
- [Prometheus Operator](https://prometheus-operator.dev/) - Official documentation
- [ServiceMonitor API](https://prometheus-operator.dev/docs/operator/api/#monitoring.coreos.com/v1.ServiceMonitor) - CRD reference

---

**Last Updated**: December 5, 2025 - v0.5.0 (Prometheus Operator migration)
