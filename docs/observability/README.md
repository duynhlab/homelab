# Observability Documentation

Comprehensive observability for the `duynhne` microservices platform -- 8 Go services, 4 PostgreSQL clusters, all running on Kubernetes with GitOps (Flux).

## Architecture

```mermaid
flowchart TD
    subgraph services [8 Microservices]
        MW["Middleware Chain<br/>Tracing → Logging → Metrics"]
    end

    subgraph pillar1 [Metrics]
        VMAgent["VMAgent<br/>scrape"]
        VMSingle["VMSingle :8428<br/>storage + query"]
    end

    subgraph pillar2 [Traces]
        OTel["OTel Collector<br/>fan-out"]
        Tempo["Tempo<br/>storage"]
        Jaeger["Jaeger :16686<br/>query UI"]
    end

    subgraph pillar3 [Logs]
        Vector["Vector<br/>DaemonSet"]
        Loki["Loki :3100"]
        VLogs["VictoriaLogs :9428"]
    end

    subgraph pillar4 [Profiles]
        Pyroscope["Pyroscope :4040"]
    end

    subgraph viz [Visualization]
        Grafana["Grafana :3000"]
    end

    subgraph alert [Alerting]
        VMAlert["VMAlert<br/>rule evaluation"]
        VMAlertmanager["VMAlertmanager<br/>routing"]
        Sloth["Sloth Operator<br/>SLO → PrometheusRules"]
    end

    MW -->|"histogram, gauge, counter"| VMAgent
    MW -->|"OTLP gRPC :4317"| OTel
    MW -->|"stdout JSON"| Vector
    MW -->|"push"| Pyroscope

    VMAgent --> VMSingle
    OTel --> Tempo
    OTel --> Jaeger
    Vector --> Loki
    Vector --> VLogs

    VMSingle --> Grafana
    Tempo --> Grafana
    Loki --> Grafana
    Jaeger --> Grafana
    Pyroscope --> Grafana

    VMSingle -->|"vmalert.proxyURL"| VMAlert
    VMAlert --> VMAlertmanager
    Sloth --> VMAlert
```

## The Four Pillars

| Pillar | Tool | Question It Answers | Docs |
|--------|------|---------------------|------|
| **Metrics** | VMSingle + VMAgent | "Is something wrong?" | [metrics/](metrics/README.md) |
| **Traces** | Tempo + Jaeger via OTel Collector | "Where is it slow?" | [tracing/](tracing/README.md) |
| **Logs** | Loki + VictoriaLogs via Vector | "Why is it broken?" | [logging/](logging/README.md) |
| **Profiles** | Pyroscope | "Which code line is the bottleneck?" | [profiling/](profiling/README.md) |

## Documentation Map

```
docs/observability/
├── README.md                     # This file (index)
├── architecture.md               # 3-layer service architecture + APM integration
│
├── metrics/                      # Pillar 1: Metrics collection & storage
│   ├── README.md                 # RED/USE/Golden Signals methodology
│   ├── victoriametrics.md        # VictoriaMetrics Operator stack
│   ├── promql-guide.md           # PromQL reference
│   └── postgresql/               # PostgreSQL-specific metrics
│       ├── monitoring.md          # Monitoring overview
│       ├── custom-metrics.md      # Custom pg_exporter queries
│       ├── pg-exporter-dashboards.md
│       └── pg-exporter-mapping.md
│
├── tracing/                      # Pillar 2: Distributed tracing
│   ├── README.md                 # Tracing guide (Tempo + OTel)
│   ├── architecture.md           # Dual backend (Tempo + Jaeger)
│   └── jaeger.md                 # Jaeger UI guide
│
├── logging/                      # Pillar 3: Structured logging
│   ├── README.md                 # Zap + Vector + Loki
│   └── victorialogs.md           # VictoriaLogs backend
│
├── profiling/                    # Pillar 4: Continuous profiling
│   └── README.md                 # Pyroscope (CPU, heap, goroutine)
│
├── grafana/                      # Visualization layer
│   ├── README.md                 # Grafana overview + plugin management
│   ├── datasources.md            # Dual datasource strategy (case study)
│   ├── dashboard-reference.md    # Microservices dashboard (34 panels)
│   └── variables.md              # Dashboard variables & regex
│
├── alerting/                     # Alerting rules
│   └── README.md                 # 2-layer alerting strategy
│
├── slo/                          # Service Level Objectives
│   ├── README.md                 # Sloth Operator + SLO targets
│   ├── alerting.md               # Multi-window burn-rate alerts
│   ├── error_budget_policy.md    # Error budget management
│   ├── getting_started.md        # Enable SLOs for a service
│   └── annotation-driven-slo-controller.md  # Future design
│
└── runbooks/                     # Operational runbooks
    ├── README.md                 # Runbook index
    ├── observability-deep-dive.md  # Theory + interview prep
    └── microservices-alerts.md     # Per-alert investigation guide
```

## Component Inventory

| Component | Namespace | Service | Port | Purpose |
|-----------|-----------|---------|------|---------|
| VMSingle | monitoring | `vmsingle-victoria-metrics` | 8428 | Metrics storage + Prometheus-compatible API |
| VMAgent | monitoring | `vmagent-victoria-metrics` | 8429 | Metrics scraping (replaces Prometheus scraper) |
| VMAlert | monitoring | `vmalert-victoria-metrics` | 8080 | Rule evaluation (alerting + recording rules) |
| VMAlertmanager | monitoring | `vmalertmanager-victoria-metrics` | 9093 | Alert routing and notification |
| Grafana | monitoring | `grafana-service` | 3000 | Dashboards and visualization |
| Tempo | monitoring | `tempo` | 3200 | Trace storage (OTLP receiver) |
| Jaeger | monitoring | `jaeger-query` | 16686 | Trace query UI (alternative to Tempo) |
| OTel Collector | monitoring | `otel-collector` | 4317 | Trace fan-out (OTLP gRPC ingress) |
| Loki | monitoring | `loki` | 3100 | Log storage and query (LogQL) |
| VictoriaLogs | monitoring | `vlsingle-victoria-logs` | 9428 | Log storage (LogsQL, alternative to Loki) |
| Vector | kube-system | DaemonSet | -- | Log collection from all pods |
| Pyroscope | monitoring | `pyroscope` | 4040 | Continuous profiling |
| Sloth | monitoring | operator | -- | SLO-to-PrometheusRule generator |

## Correlation: Connecting the Pillars

The investigation flow from alert to root cause:

```mermaid
sequenceDiagram
    participant A as Alert fires
    participant M as Metrics (Grafana)
    participant T as Traces (Tempo/Jaeger)
    participant L as Logs (Loki)
    participant P as Profiles (Pyroscope)

    A->>M: 1. Check dashboard -- which service, which signal?
    M->>T: 2. Click exemplar -- jump to trace
    T->>T: 3. Find slow span -- which operation?
    T->>L: 4. Copy trace_id -- search logs
    L->>L: 5. Read error context
    L->>P: 6. Check flamegraph -- which function?
    P->>P: 7. Identify hot code path
```

**Key correlation mechanisms:**

- **Metrics → Traces**: Exemplars on `request_duration_seconds` histogram link to trace IDs
- **Traces → Logs**: `trace_id` injected into every structured log line by LoggingMiddleware
- **Logs → Traces**: Loki derived field extracts `trace_id` and links back to Tempo
- **Traces → Profiles**: Pyroscope labels match service name for time-correlated flamegraphs

## Deployment

All components deploy via **Flux GitOps**:

```bash
make up              # Full deployment (Kind + Flux + everything)
make flux-push       # Push OCI artifacts to registry
make flux-sync       # Trigger reconciliation
make flux-status     # Check status
```

Flux reconciliation order:
1. **Controllers** -- operators, CRDs (VictoriaMetrics Operator, Prometheus CRDs, Grafana Operator, Sloth)
2. **Configs** -- monitoring stack (VMSingle, VMAgent, VMAlert, Grafana, Tempo, Loki, etc.)
3. **Apps** -- microservices (auto-discovered by VMAgent via ServiceMonitor)

## Quick Start: Accessing the Stack

```bash
# Grafana (dashboards, alerts, explore)
kubectl port-forward svc/grafana-service -n monitoring 3000:3000

# VMSingle (metrics API, VMUI)
kubectl port-forward svc/vmsingle-victoria-metrics -n monitoring 8428:8428

# Jaeger (trace search UI)
kubectl port-forward svc/jaeger-query -n monitoring 16686:16686

# Pyroscope (flamegraphs)
kubectl port-forward svc/pyroscope -n monitoring 4040:4040
```

## Related Documentation

- [3-Layer Architecture](architecture.md) -- how services integrate with APM middleware
- [Metrics: RED/USE/Golden Signals](metrics/README.md) -- metrics methodology
- [VictoriaMetrics Operator](metrics/victoriametrics.md) -- migration from kube-prometheus-stack
- [Grafana Datasources](grafana/datasources.md) -- dual datasource strategy (Prometheus vs VictoriaMetrics plugin)
- [Alerting Strategy](alerting/README.md) -- 2-layer alerting (threshold + SLO burn-rate)
- [SLO System](slo/README.md) -- Sloth Operator and burn-rate alerts
- [Interview Prep](runbooks/observability-deep-dive.md) -- RED/USE/Golden Signals theory + structured answers
