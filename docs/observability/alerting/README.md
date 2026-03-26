# Alerting Strategy

Two-layer alerting approach combining immediate threshold detection with SLO-based burn-rate alerts.

## Full Alerting Pipeline

End-to-end view of how metrics become alerts, from ingestion through evaluation to notification and visibility.

```mermaid
flowchart TD
    subgraph ingestion ["1. Metrics Ingestion"]
        Targets["Targets<br/>(8 microservices, PostgreSQL,<br/>external-secrets, Tempo)"]
        VMAgent["VMAgent<br/>(scraper)"]
        Targets -->|"ServiceMonitor<br/>PodMonitor"| VMAgent
    end

    subgraph storage ["2. Storage"]
        VMSingle["VMSingle :8428<br/>(metrics storage)"]
        VMAgent -->|"remoteWrite<br/>/api/v1/write"| VMSingle
    end

    subgraph rules ["3. Alert Rule Definitions"]
        PR["PrometheusRule<br/>(microservices, postgres,<br/>backup alerts)"]
        PSL["PrometheusServiceLevel<br/>(SLO definitions)"]
        Sloth["Sloth Operator"]
        VMOp["VM Operator"]
        VMRule["VMRule<br/>(auto-converted)"]

        PSL -->|generates| Sloth
        Sloth -->|"burn-rate<br/>PrometheusRule"| PR
        PR -->|auto-convert| VMOp
        VMOp -->|creates| VMRule
    end

    subgraph evaluation ["4. Evaluation"]
        VMAlert["VMAlert :8080<br/>(evaluates every 15s)"]
        VMRule -->|selectAllByDefault| VMAlert
        VMSingle <-->|"datasource<br/>remoteRead/Write"| VMAlert
    end

    subgraph notification ["5. Notification Routing"]
        VMAM["VMAlertmanager :9093<br/>(group, deduplicate, silence, route)"]
        VMAlert -->|"POST /api/v2/alerts"| VMAM
    end

    subgraph destinations ["6. Alert Destinations"]
        Karma["Karma :8080<br/>(alert dashboard)"]
        Grafana["Grafana<br/>(Alerting tab, drill-down)"]
        Slack["Slack / PagerDuty<br/>(planned)"]

        VMAM -.->|"reads AM API"| Karma
        VMSingle -->|"vmalert.proxyURL"| Grafana
        VMAM -.->|"webhook / pagerduty<br/>receivers (planned)"| Slack
    end
```

### Current State

- Stages 1-4 are fully operational (29+ threshold alerts, 48 SLO burn-rate alerts).
- Stage 5 (VMAlertmanager) routes alerts but has only a `default` receiver with **no notification destination**.
- Stage 6: Grafana provides read-only rule visibility via `vmalert.proxyURL`. **Karma** is the dedicated alert dashboard (reads VMAlertmanager API directly). Slack/PagerDuty integration is planned.

## VictoriaMetrics vs Prometheus: Terminology Mapping

This project uses the **VictoriaMetrics stack** instead of Prometheus. VM Operator auto-converts Prometheus CRDs, so you write standard Prometheus resources but they run on VM components.

| Prometheus Ecosystem | VictoriaMetrics Equivalent | What It Does | Deployed? |
|---|---|---|---|
| Prometheus server | **VMSingle** `:8428` | Stores metrics, exposes PromQL-compatible API | Yes |
| Prometheus scraper | **VMAgent** | Scrapes targets via ServiceMonitor/PodMonitor | Yes |
| Prometheus rule evaluator | **VMAlert** `:8080` | Evaluates alert and recording rules | Yes |
| Alertmanager | **VMAlertmanager** `:9093` | Groups, deduplicates, silences, and routes alerts | Yes |
| PrometheusRule CRD | **VMRule** (auto-converted) | Defines alert/recording rules; VM Operator converts PrometheusRule to VMRule automatically | Yes |
| PrometheusServiceLevel | (Sloth generates PrometheusRule) | SLO definitions; Sloth only supports PrometheusRule format, VM Operator converts the output | Yes |

**Why write PrometheusRule instead of VMRule?** Sloth Operator only generates `PrometheusRule` CRDs. VM Operator's `disable_prometheus_converter: false` setting auto-converts all Prometheus CRDs to VM equivalents. This gives compatibility with the broader ecosystem while running entirely on VictoriaMetrics.

## Architecture

```mermaid
flowchart TD
    subgraph layer1 ["Layer 1: Threshold Alerts"]
        PR1["PrometheusRule CRDs<br/>microservices-alerts.yaml<br/>postgres/cnpg + postgres/zalando"]
        T1["18 application alerts<br/>PostgreSQL: chart + Zalando split"]
    end

    subgraph layer2 ["Layer 2: SLO Burn-Rate Alerts"]
        PSL["PrometheusServiceLevel CRDs<br/>8 services x 3 SLOs"]
        Sloth["Sloth Operator<br/>generates multi-window burn-rate rules"]
        T2["48 SLO alerts<br/>page + ticket severity"]
    end

    subgraph pipeline ["Alert Pipeline"]
        VMOp["VM Operator<br/>auto-converts PrometheusRule to VMRule"]
        VMAlert["VMAlert<br/>evaluates all rules every 15s"]
        VMAM["VMAlertmanager<br/>deduplication, routing, silencing"]
    end

    subgraph viz [Visibility]
        Grafana["Grafana Alerting UI<br/>read-only rules via vmalert.proxyURL"]
        Karma["Karma Dashboard<br/>reads VMAlertmanager API"]
    end

    PR1 --> VMOp
    PSL --> Sloth
    Sloth -->|"PrometheusRule"| VMOp
    VMOp -->|"VMRule"| VMAlert
    VMAlert -->|"firing alerts"| VMAM
    VMAlert -->|"/api/v1/rules"| Grafana
    VMAM -.->|"AM API"| Karma
```

## Two-Layer Approach

### Layer 1: Threshold Alerts (Immediate Detection)

Direct metric threshold checks. Fire immediately when a condition is met.

**Application alerts** (`microservices-alerts.yaml`, 18 alerts, 6 groups):

| Group | Alerts | Examples |
|-------|--------|----------|
| Availability | 3 | `MicroserviceDown`, `MicroserviceHighRestartRate`, `MicroserviceAllReplicasDown` |
| Errors | 3 | `MicroserviceHighErrorRate`, `MicroserviceErrorRateSpike`, `MicroserviceHighClientErrorRate` |
| Latency | 3 | `MicroserviceHighP95Latency`, `MicroserviceHighP99Latency`, `MicroserviceLatencyDegradation` |
| Traffic | 3 | `MicroserviceNoTraffic`, `MicroserviceTrafficDrop`, `MicroserviceHighTraffic` |
| Saturation | 3 | `MicroserviceHighInFlightRequests`, `MicroserviceHighBandwidth`, `MicroserviceConnectionPoolSaturation` |
| Go Runtime | 3 | `MicroserviceHighGoroutineCount`, `MicroserviceHighMemoryUsage`, `MicroserviceFrequentGC` |

**PostgreSQL alerts** ([`prometheusrules/postgres/`](../../../kubernetes/infra/configs/monitoring/prometheusrules/postgres/README.md)): CNPG chart-aligned rules under `postgres/cnpg/` (e.g. `CNPGClusterOffline`, HA, replication, disk, logical replication) and Zalando rules under `postgres/zalando/` (`PostgresDown`, `custom_*` saturation, etc.). Backup alerts remain in `postgres-backup-alerts.yaml`.

**Recording rules** (`microservices-recording-rules.yaml`):

Pre-aggregated metrics for dashboard and alert performance:
- `job_app:request_duration_seconds:rate5m` (per-service RPS)
- `job_app:request_duration_seconds:error_rate5m` (per-service error rate)
- `job_app:request_duration_seconds:p95_5m` / `p99_5m` (latency percentiles)
- `job_app:apdex:ratio_rate5m` (Apdex score)
- `job_app:request_in_flight:sum` (in-flight requests)

### Layer 2: SLO Burn-Rate Alerts (Error Budget)

Multi-window multi-burn-rate methodology from Google SRE Workbook. Generated by **Sloth Operator** from `PrometheusServiceLevel` CRDs.

**Coverage**: 8 services x 3 SLOs = 24 SLOs, 48 alerts

| SLO Type | Target | SLI Query |
|----------|--------|-----------|
| Availability | 99.5% | `up{job="microservices"}` |
| Latency (P95) | 99.5% (< 500ms) | `request_duration_seconds_bucket{le="0.5"}` |
| Error Rate | 99.0% | `request_duration_seconds_count{code!~"5.."}` |

Each SLO generates 2 alerts:

| Alert | Window | Burn Rate | Severity | Action |
|-------|--------|-----------|----------|--------|
| Page | 5m/1h | 14.4x | critical | Wake someone up |
| Ticket | 30m/6h | 6x | warning | Fix within business hours |

**Why two layers?**

- Layer 1 catches **obvious failures** immediately (service down, error spike, disk full)
- Layer 2 catches **slow degradation** that burns error budget over time (slightly elevated latency, gradual error increase)
- Together they provide both **fast incident response** and **proactive SLO protection**

## Alert Flow

```mermaid
sequenceDiagram
    participant Git as Git Repository
    participant Flux as Flux
    participant VMOp as VM Operator
    participant VMAlert as VMAlert
    participant VMAM as VMAlertmanager

    Git->>Flux: PrometheusRule CRD committed
    Flux->>VMOp: reconcile
    VMOp->>VMOp: auto-convert PrometheusRule → VMRule
    VMOp->>VMAlert: load VMRule
    VMAlert->>VMAlert: evaluate every 15s
    VMAlert-->>VMAM: fire alert (if condition met)
    VMAM-->>VMAM: deduplicate, route, silence
```

## Grafana Visibility

**VMAlert** holds the rules; **VMSingle** proxies `/api/v1/rules` to VMAlert via `vmalert.proxyURL`. Whether **Grafana > Alerting > Alert rules** lists them as **data source–managed (read-only)** depends on Grafana’s integration with the **metrics datasource type** (VictoriaMetrics plugin vs optional `prometheus` type). With **only** the VM plugin, that page may be **empty or incomplete** even when rules are firing — this is a **UI** limitation, not missing rules.

See [Grafana Alerting and datasource types](../grafana/datasources.md#grafana-alerting-and-datasource-types) for details and alternatives (VMAlert UI, Karma, `kubectl`).

## Manifest Locations

```
kubernetes/infra/configs/monitoring/
├── prometheusrules/
│   ├── microservices-alerts.yaml           # Layer 1: 18 application alerts
│   ├── microservices-recording-rules.yaml  # Pre-aggregated recording rules
│   └── postgres/                           # Layer 1: CNPG + Zalando PrometheusRules
├── slo/
│   ├── auth.yaml                           # Layer 2: SLO definitions per service
│   ├── user.yaml
│   ├── product.yaml
│   ├── cart.yaml
│   ├── order.yaml
│   ├── review.yaml
│   ├── notification.yaml
│   └── shipping.yaml
└── victoriametrics/
    ├── vmalert.yaml                        # VMAlert (rule evaluator)
    └── vmalertmanager.yaml                 # VMAlertmanager (notification router)
```

## Alert Dashboard: Karma

[Karma](https://github.com/prymitive/karma) is the dedicated alert dashboard, reading directly from VMAlertmanager's Alertmanager-compatible API.

**Why Karma:**

- Industry-standard Alertmanager dashboard used widely in production SRE teams
- Reads VMAlertmanager API natively (zero config on AM side)
- Silence management from the UI (create/expire silences for maintenance windows)
- Multi-instance aggregation (production HA Alertmanager support)
- Alert history visualization (24h trend blocks for incident review)

**Deployment:** Raw K8s manifest in `kubernetes/infra/configs/monitoring/karma/`.

**Configuration:** Single environment variable pointing to VMAlertmanager:

```
ALERTMANAGER_URI=http://vmalertmanager-victoria-metrics.monitoring.svc:9093
```

For a detailed comparison of Karma against other alert dashboard tools (Alerta, UAR, Siren), see [Alert Dashboard Comparison](dashboard-comparison.md).

## Future Roadmap

| Phase | Scope | Status |
|-------|-------|--------|
| Layer 1: Application alerts | 18 alerts (RED + Golden Signals) | Implemented |
| Layer 1: PostgreSQL alerts | 14 alerts (availability, performance, storage) | Implemented |
| Layer 2: SLO alerts | 48 alerts (8 services x 3 SLOs x 2 severities) | Implemented |
| Alert dashboard | Karma reading VMAlertmanager API | Implemented |
| Layer 1: Database connection pool | PgBouncer/PgDog saturation alerts | Planned |
| Layer 1: Infrastructure | Node CPU/memory/disk pressure | Planned |
| Layer 1: Kubernetes | Pod OOM, CrashLoopBackOff, pending pods | Planned |
| Integration | PagerDuty/Slack routing in VMAlertmanager | Planned |

## Related Documentation

- [Alert Dashboard Comparison](dashboard-comparison.md) -- deep-dive tool comparison (Karma, Alerta, UAR, Siren, Grafana)
- [Microservices Alerts Runbook](../runbooks/microservices-alerts.md) -- per-alert investigation and resolution
- [SLO System](../slo/README.md) -- Sloth Operator, SLO targets, error budgets
- [SLO Alerting](../slo/alerting.md) -- burn-rate methodology details
- [Grafana Datasources](../grafana/datasources.md) -- how read-only rules display works
- [Observability Deep Dive](../runbooks/observability-deep-dive.md) -- theory and interview prep
