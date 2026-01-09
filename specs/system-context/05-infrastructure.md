# 05. Infrastructure

> **Purpose**: Shared infrastructure components - middleware, Helm charts, deployment scripts, Kubernetes resources, CI/CD.

---

## Table of Contents

- [Middleware Stack](#middleware-stack)
- [Helm Chart System](#helm-chart-system)
- [Deployment Scripts](#deployment-scripts)
- [Kubernetes Resources](#kubernetes-resources)
- [CI/CD Pipeline](#cicd-pipeline)

---

## Middleware Stack

### Overview

**Location**: `services/pkg/middleware/`

All 9 microservices share the same middleware stack for consistent observability:

| Middleware | File | Purpose | Order |
|------------|------|---------|-------|
| **Tracing** | `tracing.go` | OpenTelemetry span creation | 1st (context propagation) |
| **Logging** | `logging.go` | Structured logging with trace-id | 2nd (before metrics) |
| **Prometheus** | `prometheus.go` | Request metrics collection | 3rd (after logging) |
| **Profiling** | `profiling.go` | Pyroscope profiling | Startup (not middleware) |
| **Resource** | `resource.go` | Kubernetes service detection | Utility |

### Middleware Order (Critical!)

```go
r := gin.Default()

// 1. Tracing middleware (MUST BE FIRST for context propagation)
r.Use(middleware.TracingMiddleware())

// 2. Logging middleware (MUST BE BEFORE Prometheus for trace-id)
r.Use(middleware.LoggingMiddleware(logger))

// 3. Prometheus middleware (collects metrics from requests)
r.Use(middleware.PrometheusMiddleware())
```

**Why this order?**
1. **Tracing first**: Creates W3C Trace Context, all subsequent middleware can access trace-id
2. **Logging second**: Uses trace-id from context, logs BEFORE Prometheus (to log errors)
3. **Prometheus last**: Measures entire request including logging overhead

### 1. Tracing Middleware

**File**: `services/pkg/middleware/tracing.go` (261 lines)

**Key Functions:**

```go
// Initialize OpenTelemetry with auto-detection
func InitTracing() (*sdktrace.TracerProvider, error)

// Create tracing middleware for Gin
func TracingMiddleware() gin.HandlerFunc

// Start a new span with attributes
func StartSpan(ctx context.Context, name string, opts ...trace.SpanStartOption) (context.Context, trace.Span)

// Shutdown tracer provider gracefully
func Shutdown(ctx context.Context) error
```

**Features:**
- **Auto-detection**: Service name from Kubernetes pod name
- **10% sampling**: Configurable via `OTEL_SAMPLE_RATE`
- **Request filtering**: Skip `/health`, `/metrics`
- **W3C Trace Context**: Standard propagation format
- **Graceful shutdown**: Flush pending spans on exit

**Configuration**:
```go
type TracingConfig struct {
    ServiceName      string    // Auto-detected: "auth", "user", etc.
    ServiceNamespace string    // Auto-detected: "auth", "user", etc.
    TempoEndpoint    string    // "tempo.monitoring.svc.cluster.local:4318"
    Insecure         bool      // true (no TLS)
    SampleRate       float64   // 0.1 (10%)
    ExportTimeout    time.Duration
    BatchTimeout     time.Duration
    SkipPaths        []string  // ["/health", "/metrics"]
}
```

### 2. Logging Middleware

**File**: `services/pkg/middleware/logging.go` (139 lines)

**Key Functions:**

```go
// Create structured logger (Zap)
func NewLogger() (*zap.Logger, error)

// Logging middleware for Gin
func LoggingMiddleware(logger *zap.Logger) gin.HandlerFunc

// Extract trace-id from headers
func GetTraceID(c *gin.Context) string

// Get logger from Gin context
func GetLoggerFromGinContext(c *gin.Context) *zap.Logger
```

**Features:**
- **JSON logs**: Structured output for parsing
- **Trace-ID extraction**: From `traceparent` header (W3C) or generate new
- **Trace-ID propagation**: Inject into Gin context for handlers
- **Log levels**: Auto-detect (info for 2xx/3xx, error for 4xx/5xx)
- **Response header**: Add `X-Trace-ID` to response

**JSON Log Format:**
```json
{
  "level": "info",
  "timestamp": "2025-12-10T10:30:45.123Z",
  "caller": "middleware/logging.go:92",
  "message": "HTTP request",
  "trace_id": "2db2fe7dcd3c8cb8cb4647ea2b455a21",
  "method": "GET",
  "path": "/api/v1/products",
  "status": 200,
  "duration": 0.025,
  "client_ip": "10.244.1.5",
  "user_agent": "k6/1.4.2"
}
```

### 3. Prometheus Middleware

**File**: `services/pkg/middleware/prometheus.go` (79 lines)

**Key Functions:**

```go
// Prometheus middleware for Gin
func PrometheusMiddleware() gin.HandlerFunc
```

**Metrics Collected:**

```go
// Request duration histogram
requestDuration := prometheus.NewHistogramVec(
    prometheus.HistogramOpts{
        Name:    "request_duration_seconds",
        Help:    "HTTP request latency in seconds",
        Buckets: []float64{0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 2, 5},
    },
    []string{"method", "path", "code"},
)

// Request counter
requestsTotal := prometheus.NewCounterVec(
    prometheus.CounterOpts{
        Name: "requests_total",
        Help: "Total HTTP requests",
    },
    []string{"method", "path", "code"},
)

// In-flight requests gauge
requestsInFlight := prometheus.NewGaugeVec(
    prometheus.GaugeOpts{
        Name: "requests_in_flight",
        Help: "Current number of HTTP requests being processed",
    },
    []string{"method", "path"},
)
```

**Labels** (added by app):
- `method`: HTTP method (GET, POST, PUT, DELETE)
- `path`: Request path (`/api/v1/products`)
- `code`: HTTP status code (200, 404, 500)

**Labels** (added by Prometheus via ServiceMonitor):
- `job`: `"microservices"` (all services)
- `app`: Service name (auth, user, product, etc.)
- `service`: Kubernetes service name
- `namespace`: Kubernetes namespace
- `instance`: Pod IP:port

### 4. Profiling Middleware

**File**: `services/pkg/middleware/profiling.go` (57 lines)

**Key Functions:**

```go
// Initialize Pyroscope profiling
func InitProfiling() error

// Stop profiling
func StopProfiling()
```

**Profile Types**:
- `ProfileCPU`: CPU usage
- `ProfileAllocObjects`: Heap allocations (count)
- `ProfileAllocSpace`: Heap allocations (bytes)
- `ProfileInuseObjects`: Live objects
- `ProfileInuseSpace`: Live memory
- `ProfileGoroutines`: Goroutine count
- `ProfileMutexCount`: Mutex contention (count)
- `ProfileMutexDuration`: Mutex contention (duration)
- `ProfileBlockCount`: Blocking events (count)
- `ProfileBlockDuration`: Blocking events (duration)

### 5. Resource Detection

**File**: `services/pkg/middleware/resource.go` (130 lines)

**Key Functions:**

```go
// Create OpenTelemetry resource with auto-detection
func CreateResource(ctx context.Context) (*resource.Resource, error)

// Detect service name from Kubernetes pod name
func detectServiceInfo() (serviceName string, namespace string)

// Get service name from resource
func GetServiceName(res *resource.Resource) string
```

**Service Name Detection Logic:**

```go
// Parse Kubernetes pod name
// Example: "auth-deployment-7d6f8b9c5-abc12"
// Extract: "auth"

func detectServiceInfo() (string, string) {
    podName := os.Getenv("HOSTNAME")  // Set by Kubernetes
    namespace := os.Getenv("NAMESPACE")
    
    // Parse: <service-name>-deployment-<rs-hash>-<pod-hash>
    parts := strings.Split(podName, "-")
    if len(parts) >= 3 {
        // Join all parts except last 2 (hash + hash)
        serviceName = strings.Join(parts[:len(parts)-2], "-")
    }
    
    return serviceName, namespace
}
```

**Handles hyphenated names**:
- `shipping-v2-deployment-abc-xyz` → `shipping-v2` ✅
- `auth-deployment-abc-xyz` → `auth` ✅

---

## Helm Chart System

### Generic Helm Chart

**Chart**: `charts/` (version 0.2.0)
**Purpose**: One chart for all 9 microservices

**Files**:
- `Chart.yaml`: Chart metadata
- `values.yaml`: Default values
- `values/*.yaml`: Per-service overrides (9 files)
- `templates/deployment.yaml`: Deployment template
- `templates/service.yaml`: Service template
- `templates/_helpers.tpl`: Template helpers

### Chart Metadata

**File**: `charts/Chart.yaml`

```yaml
apiVersion: v2
name: microservice
description: A generic Helm chart for deploying Go microservices
type: application
version: 0.2.0
appVersion: "1.0.0"
maintainers:
  - name: duynhne
    url: https://github.com/duynhne
keywords:
  - microservice
  - go
  - monitoring
  - prometheus
```

### Default Values

**File**: `charts/values.yaml` (112 lines)

**Key sections**:

```yaml
# Service configuration
name: ""  # REQUIRED: Set via per-service values
namespace: ""  # REQUIRED: Set via per-service values
replicaCount: 2

# Image configuration
image:
  repository: ghcr.io/duynhne
  name: ""  # REQUIRED: Short name (auth, user, product)
  tag: v6
  pullPolicy: IfNotPresent

# Service networking
service:
  type: ClusterIP
  port: 8080
  targetPort: 8080
  portName: http

# Resource limits
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"

# Health probes
livenessProbe:
  enabled: true
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  enabled: true
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5

# Extra environment variables (NEW in v0.2.0)
extraEnv: []

# Tracing configuration
tracing:
  enabled: true
  endpoint: "tempo.monitoring.svc.cluster.local:4318"
  sampleRate: "0.1"  # 10% sampling
```

### extraEnv Pattern

**Purpose**: Inject custom environment variables without duplicating `env:` blocks

**Example**: `charts/values/auth.yaml`

```yaml
name: auth
namespace: auth
image:
  name: auth
  tag: v6

# Custom environment variables
extraEnv:
  - name: JWT_SECRET
    value: "my-secret-key"
  - name: TOKEN_EXPIRY
    value: "3600"
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: auth-secret
        key: db-url
```

**Template implementation**: `charts/templates/deployment.yaml`

```yaml
{{- if or .Values.env .Values.extraEnv .Values.tracing.enabled }}
env:
{{- with .Values.env }}
  {{- toYaml . | nindent 12 }}
{{- end }}
{{- if .Values.tracing.enabled }}
  - name: TEMPO_ENDPOINT
    value: {{ .Values.tracing.endpoint | quote }}
  - name: OTEL_SAMPLE_RATE
    value: {{ .Values.tracing.sampleRate | quote }}
{{- end }}
{{- with .Values.extraEnv }}
  {{- toYaml . | nindent 12 }}
{{- end }}
{{- end }}
```

**Benefits**:
- ✅ No duplicate `env:` blocks
- ✅ Flexible: can add env vars via `.Values.env` or `.Values.extraEnv`
- ✅ Tracing config automatically injected
- ✅ Clean YAML output

### Per-Service Values

**9 files in `charts/values/`:**

1. `auth.yaml` - Auth service
2. `user.yaml` - User service
3. `product.yaml` - Product service
4. `cart.yaml` - Cart service
5. `order.yaml` - Order service
6. `review.yaml` - Review service
7. `notification.yaml` - Notification service
8. `shipping.yaml` - Shipping service (v1)
9. `shipping-v2.yaml` - Shipping-v2 service

**Example**: `charts/values/auth.yaml`

```yaml
name: auth
namespace: auth

image:
  name: auth
  tag: v6

replicaCount: 2

resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"

labels:
  app: auth
  component: api

tracing:
  enabled: true
  endpoint: "tempo.monitoring.svc.cluster.local:4318"
  sampleRate: "0.1"
```

### Unified Dockerfile

**File**: `services/Dockerfile`

**Multi-stage build** for all 9 services:

```dockerfile
# Build stage
FROM golang:1.23.0-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Build argument for service name
ARG SERVICE_NAME
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/service ./cmd/${SERVICE_NAME}

# Runtime stage
FROM alpine:latest

WORKDIR /root/
COPY --from=builder /app/service .

EXPOSE 8080
CMD ["./service"]
```

**Build command**:
```bash
docker build --build-arg SERVICE_NAME=auth -t ghcr.io/duynhne/auth:v6 -f services/Dockerfile services/
```

---

## Deployment Scripts

### Script Organization

**12 numbered scripts** in `scripts/` directory:

```
scripts/
├── 01-create-kind-cluster.sh       # Infrastructure
├── 03-deploy-monitoring.sh         # Monitoring Stack (includes metrics)
├── 04-deploy-apm.sh                # APM Stack (all components)
├── 04a-deploy-tempo.sh             # APM Stack (Tempo only)
├── 04b-deploy-pyroscope.sh         # APM Stack (Pyroscope only)
├── 04c-deploy-loki.sh              # APM Stack (Loki + Vector)
├── 05-build-microservices.sh       # Build & Deploy (build images)
├── 06-deploy-microservices.sh      # Build & Deploy (deploy services)
├── 07-deploy-k6.sh                 # Load Testing
├── 08-deploy-slo.sh                # SLO System
├── 09-setup-access.sh              # Access Setup
├── 10-reload-dashboard.sh          # Utilities
├── 11-diagnose-latency.sh          # Utilities
└── 12-error-budget-alert.sh        # Utilities
```

### Deployment Order

**Sequential execution** (each phase depends on previous):

1. **Infrastructure** (01-02)
2. **Monitoring Stack** (03) - BEFORE apps
3. **APM Stack** (04) - BEFORE apps
4. **Build & Deploy Apps** (05-06)
5. **Load Testing** (07) - AFTER apps
6. **SLO System** (08)
7. **Access Setup** (09)

### Key Scripts

#### 05-build-microservices.sh

**Purpose**: Build Docker images for all 9 services

```bash
#!/bin/bash
set -e

SERVICES=("auth" "user" "product" "cart" "order" "review" "notification" "shipping" "shipping-v2")
IMAGE_TAG="v5"
REGISTRY="ghcr.io/duynhne"

for SERVICE in "${SERVICES[@]}"; do
    echo "Building $SERVICE..."
    docker build \
        --build-arg SERVICE_NAME=$SERVICE \
        -t $REGISTRY/$SERVICE:$IMAGE_TAG \
        -f services/Dockerfile services/
    
    # Optional: Push to registry
    # docker push $REGISTRY/$SERVICE:$IMAGE_TAG
done

echo "✅ All images built successfully!"
```

#### 06-deploy-microservices.sh

**Purpose**: Deploy all 9 services via Helm

```bash
#!/bin/bash
set -e

SERVICES=("auth" "user" "product" "cart" "order" "review" "notification" "shipping" "shipping-v2")
CHART_VERSION=$(grep '^version:' charts/Chart.yaml | awk '{print $2}')
MODE="${1:---local}"  # --local or --registry

if [[ "$MODE" == "--registry" ]]; then
    CHART_REF="oci://ghcr.io/duynhne/charts/microservice"
else
    CHART_REF="charts/"
fi

for SERVICE in "${SERVICES[@]}"; do
    NAMESPACE=$(yq eval '.namespace' charts/values/$SERVICE.yaml)
    
    echo "Deploying $SERVICE to $NAMESPACE (chart v$CHART_VERSION)..."
    
    helm upgrade --install $SERVICE $CHART_REF \
        -f charts/values/$SERVICE.yaml \
        -n $NAMESPACE \
        --create-namespace \
        --version "$CHART_VERSION" \
        --wait --timeout 120s
done

echo "✅ All services deployed successfully!"
```

**Usage**:
```bash
# Deploy from local chart
./scripts/05-deploy-microservices.sh --local

# Deploy from OCI registry
./scripts/05-deploy-microservices.sh --registry
```

---

## Kubernetes Resources

### ServiceMonitor (Auto-Discovery)

**File**: `k8s/prometheus/servicemonitor-microservices.yaml`

**Purpose**: Auto-discover and scrape all microservices

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: microservices
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchExpressions:
      - key: app
        operator: In
        values: [auth, user, product, cart, order, review, notification, shipping, shipping-v2]
  namespaceSelector:
    matchLabels:
      monitoring: enabled
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
      relabelings:
        - sourceLabels: [__meta_kubernetes_service_label_app]
          targetLabel: app
        - sourceLabels: [__meta_kubernetes_service_name]
          targetLabel: service
        - sourceLabels: [__meta_kubernetes_namespace]
          targetLabel: namespace
        - targetLabel: job
          replacement: microservices
```

### PrometheusRules (SLO)

**Generated by Sloth Operator** from PrometheusServiceLevel CRDs

**Example**: `auth-slo-requests-availability` (auto-generated)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: auth-slo-requests-availability
  namespace: monitoring
spec:
  groups:
    - name: sloth-slo-sli-recordings-auth-requests-availability
      rules:
        - record: slo:sli_error:ratio_rate5m
          expr: sum(rate(requests_total{job="microservices",app="auth",code=~"5.."}[5m])) / sum(rate(requests_total{job="microservices",app="auth"}[5m]))
          labels:
            sloth_service: auth
            sloth_slo: requests-availability
    
    - name: sloth-slo-meta-recordings-auth-requests-availability
      rules:
        - record: slo:error_budget:ratio
          expr: (1 - 0.999) - slo:sli_error:ratio_rate5m{sloth_service="auth"}
          labels:
            sloth_service: auth
            sloth_slo: requests-availability
    
    - name: sloth-slo-alerts-auth-requests-availability
      rules:
        - alert: AuthHighErrorRate
          expr: slo:sli_error:ratio_rate1h{sloth_service="auth"} > 14 * (1 - 0.999)
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "High error rate on auth service"
```

### GrafanaDashboard CRs

**Managed by Grafana Operator**:

1. **microservices-monitoring-001**: Main 32-panel dashboard
2. **slo-overview**: SLO summary (ID: 14643)
3. **slo-detailed**: Detailed SLO metrics (ID: 14348)
4. **tempo-observability**: Tempo metrics (custom 8-panel)
5. **vector-monitoring**: Vector self-monitoring (ID: 21954)

**Example**: `k8s/grafana-operator/dashboards/grafana-dashboard-main.yaml`

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: microservices-monitoring
  namespace: monitoring
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  folder: "Microservices"
  configMapRef:
    name: grafana-dashboard-main
    key: microservices-dashboard.json
  datasources:
    - inputName: DS_PROMETHEUS
      datasourceName: Prometheus
```

---

## CI/CD Pipeline

### GitHub Actions

**Files**:
- `.github/workflows/build-images.yml` - Build microservice images
- `.github/workflows/build-k6-images.yml` - Build k6 image

### Build Images Workflow

**File**: `.github/workflows/build-images.yml`

```yaml
name: Build and Push Microservice Images

on:
  push:
    branches: [main, develop]
    paths:
      - 'services/**'
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [auth, user, product, cart, order, review, notification, shipping, shipping-v2]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: ./services
          file: ./services/Dockerfile
          build-args: SERVICE_NAME=${{ matrix.service }}
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/${{ matrix.service }}:v6
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**Triggers**:
- Push to `main` or `develop` branches
- Changes in `services/` directory
- Manual workflow dispatch

**Output**:
- 9 Docker images pushed to `ghcr.io/duynhne/<service>:v6`

### OCI Registry

**Registry**: GitHub Container Registry (ghcr.io)

**Images**:
- `ghcr.io/duynhne/auth:v6`
- `ghcr.io/duynhne/user:v6`
- `ghcr.io/duynhne/product:v6`
- `ghcr.io/duynhne/cart:v6`
- `ghcr.io/duynhne/order:v6`
- `ghcr.io/duynhne/review:v6`
- `ghcr.io/duynhne/notification:v6`
- `ghcr.io/duynhne/shipping:v6`
- `ghcr.io/duynhne/shipping-v2:v6`
- `ghcr.io/duynhne/k6:scenarios`

**Helm Charts**:
- `oci://ghcr.io/duynhne/charts/microservice:0.2.0`

---

**Next**: Continue to [06. Technology Stack](06-technology-stack.md) →

