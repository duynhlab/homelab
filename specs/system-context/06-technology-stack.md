# 06. Technology Stack

> **Purpose**: Complete list of technologies, frameworks, libraries, and tools with versions.

---

## Table of Contents

- [Programming Languages & Frameworks](#programming-languages--frameworks)
- [Infrastructure & Deployment](#infrastructure--deployment)
- [Monitoring & Observability](#monitoring--observability)
- [Load Testing](#load-testing)
- [Development Tools](#development-tools)

---

## Programming Languages & Frameworks

### Go 1.23.0

**Primary language** for all 9 microservices

**Why Go?**
- Fast compilation and execution
- Built-in concurrency (goroutines)
- Small binary size
- Strong standard library
- Excellent cloud-native ecosystem

### Go Dependencies

**Source**: `services/go.mod`

#### Core Framework

| Package | Version | Purpose |
|---------|---------|---------|
| `github.com/gin-gonic/gin` | v1.10.1 | HTTP web framework |
| `go.uber.org/zap` | v1.27.0 | Structured logging |

#### Observability

| Package | Version | Purpose |
|---------|---------|---------|
| `go.opentelemetry.io/otel` | v1.38.0 | OpenTelemetry API |
| `go.opentelemetry.io/otel/sdk` | v1.38.0 | OpenTelemetry SDK |
| `go.opentelemetry.io/otel/trace` | v1.38.0 | Tracing primitives |
| `go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp` | v1.38.0 | OTLP HTTP exporter |
| `go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin` | v0.63.0 | Gin auto-instrumentation |
| `github.com/prometheus/client_golang` | v1.17.0 | Prometheus metrics |
| `github.com/grafana/pyroscope-go` | v1.2.7 | Continuous profiling |

#### Dependencies (Transitive)

| Package | Version | Purpose |
|---------|---------|---------|
| `github.com/google/uuid` | v1.6.0 | UUID generation |
| `golang.org/x/net` | v0.43.0 | Network utilities |
| `google.golang.org/grpc` | v1.75.0 | gRPC framework |
| `google.golang.org/protobuf` | v1.36.8 | Protocol Buffers |

---

## Infrastructure & Deployment

### Kubernetes

**Distribution**: Kind (Kubernetes in Docker)
**Purpose**: Local development cluster

**Version**:
```bash
$ kubectl version --short
Client Version: v1.33.0
Server Version: v1.33.0
```

**Kind Configuration**: `k8s/kind/kind-config.yaml`

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: monitoring-cluster
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
  - role: worker
```

**Resources**:
- 1 control-plane node
- 2 worker nodes
- Recommended: 12 CPU cores, 32GB RAM

### Helm 3

**Version**: v3.x
**Purpose**: Package manager for Kubernetes

**Charts used**:
- `prometheus-community/kube-prometheus-stack` v80.0.0
- `grafana/grafana-operator` v5.20.0
- `sloth/sloth` v0.15.0
- Custom: `charts/microservice` v0.2.0

**Commands**:
```bash
helm version --short
# version.BuildInfo{Version:"v3.16.0"}
```

### Docker

**Version**: 20.10+ or Docker Desktop
**Purpose**: Container runtime

**Images**:
- `alpine:latest` (base image)
- `golang:1.23.0-alpine` (builder image)
- `ghcr.io/duynhne/*:v5` (microservices)

---

## Monitoring & Observability

### Prometheus Ecosystem

#### Prometheus Operator

**Chart**: `prometheus-community/kube-prometheus-stack`
**Version**: v80.0.0
**Includes**:
- Prometheus v2.x
- Alertmanager v0.x
- node-exporter
- kube-state-metrics v2.x
- Grafana v11.x (bundled, but we use Grafana Operator instead)

**Configuration**: `k8s/prometheus/values.yaml`

**Features**:
- ServiceMonitor CRDs
- PrometheusRule CRDs
- Automatic scrape config generation
- Multi-namespace monitoring

#### metrics-server

**Version**: Latest (from metrics-server Helm repo)
**Namespace**: kube-system
**Purpose**: Resource metrics API (CPU/memory usage)

**Configuration**: `k8s/metrics/metrics-server-values.yaml`

**Key Features**:
- kubectl top nodes/pods support
- Horizontal Pod Autoscaler (HPA) data source
- Kind-specific configuration (`--kubelet-insecure-tls`)
- 15-second metric resolution

**Resources**:
- Requests: 50m CPU, 64Mi memory
- Limits: 100m CPU, 128Mi memory

#### Grafana Operator

**Chart**: `grafana/grafana-operator`
**Version**: v5.20.0
**CRDs**:
- `Grafana` - Grafana instance
- `GrafanaDatasource` - Datasource config
- `GrafanaDashboard` - Dashboard config

**Grafana Version**: v11.x (managed by operator)

**Configuration**: `k8s/grafana-operator/values.yaml`

**Features**:
- Declarative dashboard management
- Auto-reload on ConfigMap changes
- Multi-datasource support

### APM Stack

#### Grafana Tempo

**Version**: v2.9.0
**Purpose**: Distributed tracing backend

**Key Features**:
- OTLP HTTP/gRPC ingestion (ports 4318/4317)
- TraceQL query language
- Metrics-generator for service graphs
- Monolithic mode (single instance)

**Configuration**: `k8s/tempo/configmap.yaml`

**Storage**: Local filesystem (demo mode)

#### Grafana Loki

**Version**: v3.6.2
**Purpose**: Log aggregation

**Key Features**:
- LogQL query language
- Pattern ingestion (NEW in v3.6.2)
- Label indexing
- BoltDB + Filesystem storage

**Configuration**: `k8s/loki/configmap.yaml`

**Retention**: 7 days (168h)

#### Vector

**Version**: Latest (from Vector Helm repo)
**Purpose**: Log collection agent

**Deployment**: DaemonSet in `kube-system` namespace

**Key Features**:
- Kubernetes logs collection
- JSON log parsing
- Loki shipping
- Self-monitoring (metrics on port 9090)

**Configuration**: `k8s/vector/configmap.yaml`

#### Pyroscope

**Version**: Latest
**Purpose**: Continuous profiling

**Profile Types**:
- CPU
- Heap (allocations + in-use)
- Goroutines
- Mutex
- Block

**Configuration**: `k8s/pyroscope/configmap.yaml`

**Storage**: Local filesystem

**Retention**: 7 days (168h)

### SLO System

#### Sloth Operator

**Chart**: `sloth/sloth`
**Version**: v0.15.0
**Purpose**: SLO management

**Key Features**:
- PrometheusServiceLevel CRD
- Automatic rule generation
- Multi-window burn rates (1h, 6h, 1d, 3d)
- Error budget tracking

**Configuration**: `k8s/sloth/values.yaml`

**CRDs**: 9 PrometheusServiceLevel definitions (one per service)

---

## Load Testing

### K6

**Version**: Grafana k6/1.4.2
**Purpose**: Load testing and performance validation

**Docker Image**: `ghcr.io/duynhne/k6:scenarios`

**Test Script**: `k6/load-test-multiple-scenarios.js`

**Configuration**:
- **Duration**: 6.5 hours (390 minutes)
- **Peak VUs**: 250 (100 browser + 75 shopping + 37 registered + 25 API + 13 admin)
- **RPS**: 250-1000 sustained (avg ~400 RPS)
- **Total Requests**: 3-4 million
- **Resource**: 2 CPU / 4GB RAM

**Journey Types**: 8 user journeys
1. E-commerce Shopping Journey (9 services)
2. Product Review Journey (5 services)
3. Order Tracking Journey (6 services)
4. Quick Browse Journey (4 services)
5. API Monitoring Journey (7 services)
6. Timeout/Retry Journey (edge case)
7. Concurrent Operations Journey (edge case)
8. Error Handling Journey (edge case)

**Load Pattern**: 8-phase time-based simulation
- Morning Ramp-Up (45m)
- Morning Peak (90m)
- Lunch Dip (45m)
- Afternoon Recovery (45m)
- Evening Peak (90m)
- Evening Wind-Down (45m)
- Night Low (22m)
- Graceful Shutdown (8m)

---

## Development Tools

### Version Control

| Tool | Version | Purpose |
|------|---------|---------|
| Git | 2.x | Source control |
| GitHub | - | Code hosting, CI/CD |

### CI/CD

| Tool | Purpose |
|------|---------|
| GitHub Actions | Build and push Docker images |
| Docker Buildx | Multi-platform builds |
| GHCR | Container registry |

### Scripts

| Language | Purpose | Files |
|----------|---------|-------|
| Bash | Deployment automation | `scripts/*.sh` (12 scripts) |
| Yaml | Configuration | `k8s/`, `charts/` |

### Documentation

| Format | Purpose | Files |
|--------|---------|-------|
| Markdown | Documentation | `docs/**/*.md`, `specs/**/*.md` |
| Mermaid | Diagrams | Embedded in Markdown |
| JSON | Dashboards | `k8s/grafana-operator/dashboards/*.json` |

---

## Complete Dependency Tree

### Go Module Dependencies

**From `services/go.mod`:**

```
github.com/duynhne/monitoring
├── github.com/gin-gonic/gin v1.10.1
│   ├── github.com/gin-contrib/sse v1.1.0
│   ├── github.com/go-playground/validator/v10 v10.27.0
│   ├── github.com/goccy/go-json v0.10.5
│   ├── github.com/json-iterator/go v1.1.12
│   ├── github.com/mattn/go-isatty v0.0.20
│   ├── github.com/pelletier/go-toml/v2 v2.2.4
│   ├── github.com/ugorji/go/codec v1.3.0
│   ├── golang.org/x/net v0.43.0
│   └── google.golang.org/protobuf v1.36.8
│
├── github.com/grafana/pyroscope-go v1.2.7
│   ├── github.com/google/uuid v1.6.0
│   └── github.com/grafana/pyroscope-go/godeltaprof v0.1.9
│
├── github.com/prometheus/client_golang v1.17.0
│   ├── github.com/beorn7/perks v1.0.1
│   ├── github.com/cespare/xxhash/v2 v2.3.0
│   ├── github.com/prometheus/client_model v0.4.1-0
│   ├── github.com/prometheus/common v0.44.0
│   └── github.com/prometheus/procfs v0.11.1
│
├── go.opentelemetry.io/otel v1.38.0
│   ├── go.opentelemetry.io/otel/metric v1.38.0
│   └── go.opentelemetry.io/otel/trace v1.38.0
│
├── go.opentelemetry.io/otel/sdk v1.38.0
│   ├── go.opentelemetry.io/otel v1.38.0
│   └── golang.org/x/sys v0.35.0
│
├── go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.38.0
│   ├── go.opentelemetry.io/otel/exporters/otlp/otlptrace v1.38.0
│   ├── go.opentelemetry.io/proto/otlp v1.7.1
│   └── google.golang.org/grpc v1.75.0
│
├── go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin v0.63.0
│   ├── go.opentelemetry.io/otel v1.38.0
│   └── go.opentelemetry.io/otel/trace v1.38.0
│
└── go.uber.org/zap v1.27.0
    ├── go.uber.org/multierr v1.11.0
    └── golang.org/x/text v0.28.0
```

### Helm Chart Dependencies

**Prometheus Stack:**
```
kube-prometheus-stack v80.0.0
├── prometheus v2.x
├── alertmanager v0.x
├── node-exporter
├── kube-state-metrics v2.x
└── grafana v11.x (optional, disabled in our setup)

metrics-server (separate chart)
└── metrics-server latest (deployed to kube-system)
```

**Grafana Operator:**
```
grafana-operator v5.20.0
└── grafana v11.x (managed as CRD)
```

**Sloth:**
```
sloth v0.15.0
└── sloth binary (generates Prometheus rules)
```

---

## Version Compatibility Matrix

| Component | Version | Requires | Compatible With |
|-----------|---------|----------|-----------------|
| Go | 1.23.0 | - | All dependencies |
| Gin | v1.10.1 | Go 1.21+ | - |
| OpenTelemetry | v1.38.0 | Go 1.21+ | Tempo v2.9.0 |
| Prometheus Operator | v80.0.0 | Kubernetes 1.25+ | Sloth v0.15.0 |
| Grafana Operator | v5.20.0 | Kubernetes 1.25+ | Grafana v11.x |
| Tempo | v2.9.0 | - | OpenTelemetry v1.x |
| Loki | v3.6.2 | - | Vector latest |
| Sloth | v0.15.0 | Prometheus Operator | - |
| K6 | v1.4.2 | - | - |

---

## Upgrade Notes

### Go 1.23.0 → 1.24.x

**Safe**: Minor version upgrades usually backward compatible
**Steps**:
1. Update `go.mod`: `go 1.24`
2. Update Dockerfile: `FROM golang:1.24.0-alpine`
3. Run `go mod tidy`
4. Test locally

### Prometheus Operator v80 → v81

**Check**: Release notes for breaking changes
**Steps**:
1. Backup CRDs: `kubectl get crds -o yaml > crds-backup.yaml`
2. Update Helm values if needed
3. Run: `helm upgrade prometheus-kube-prometheus-stack ...`
4. Verify: `kubectl get servicemonitors -A`

### OpenTelemetry v1.38 → v1.39

**Safe**: Patch versions safe, minor versions check changelog
**Steps**:
1. Update `go.mod`
2. Run `go mod tidy`
3. Test tracing locally
4. Redeploy services

---

## External Resources

### Official Documentation

- **Go**: https://go.dev/doc/
- **Kubernetes**: https://kubernetes.io/docs/
- **Helm**: https://helm.sh/docs/
- **Prometheus**: https://prometheus.io/docs/
- **Grafana**: https://grafana.com/docs/
- **OpenTelemetry**: https://opentelemetry.io/docs/
- **Tempo**: https://grafana.com/docs/tempo/
- **Loki**: https://grafana.com/docs/loki/
- **Pyroscope**: https://grafana.com/docs/pyroscope/
- **K6**: https://grafana.com/docs/k6/

### GitHub Repositories

- **Prometheus Operator**: https://github.com/prometheus-operator/prometheus-operator
- **Grafana Operator**: https://github.com/grafana/grafana-operator
- **Sloth**: https://github.com/sloth-dev/sloth
- **OpenTelemetry Go**: https://github.com/open-telemetry/opentelemetry-go

---

**Next**: Continue to [07. Data Flows](07-data-flows.md) →

