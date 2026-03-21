# VictoriaMetrics Operator Stack

This platform uses the **VictoriaMetrics Operator** to manage the complete metrics and logging stack via Kubernetes CRDs. It replaces the previous `kube-prometheus-stack` (Prometheus server + Prometheus Operator) with a fully operator-managed setup that provides lower resource usage, Prometheus API compatibility, and consistent configuration across environments.

## Architecture

```mermaid
flowchart TD
    subgraph helmCharts ["Helm Charts (controllers)"]
        PromCRDs["prometheus-operator-crds<br/>Installs Prometheus CRDs only"]
        VMOp["victoria-metrics-operator<br/>Installs VM Operator + VM CRDs"]
    end

    subgraph promCRDs ["Prometheus CRDs (monitoring.coreos.com/v1)"]
        SM["ServiceMonitor"]
        PM["PodMonitor"]
        PR["PrometheusRule"]
    end

    subgraph thirdParty ["Third-party Charts / Manual"]
        Valkey["Valkey<br/>creates ServiceMonitor"]
        Sloth["Sloth<br/>creates PrometheusRule"]
        CNPG["CloudNativePG<br/>creates PodMonitor"]
        Manual["Your YAML files<br/>ServiceMonitors, PodMonitors,<br/>PrometheusRules"]
    end

    subgraph vmConverter ["VM Operator: Prometheus Converter"]
        Conv["Watches monitoring.coreos.com<br/>Auto-converts to VM equivalents"]
    end

    subgraph vmCRDs ["VM CRDs (operator.victoriametrics.com/v1beta1)"]
        VMSS["VMServiceScrape"]
        VMPS["VMPodScrape"]
        VMR["VMRule"]
    end

    subgraph vmRuntime ["VM Runtime Components"]
        VMAgent["VMAgent<br/>Scrapes metrics"]
        VMSingle["VMSingle<br/>Stores metrics"]
        VMAlert["VMAlert<br/>Evaluates rules"]
        VMAMgr["VMAlertmanager<br/>Routes alerts"]
        VLSingle["VLSingle<br/>Stores logs"]
    end

    subgraph consumers ["Consumers"]
        Grafana["Grafana<br/>Dashboards + Queries"]
        Vector["Vector<br/>Ships logs"]
    end

    PromCRDs -->|registers| SM
    PromCRDs -->|registers| PM
    PromCRDs -->|registers| PR

    Valkey --> SM
    Sloth --> PR
    CNPG --> PM
    Manual --> SM
    Manual --> PM
    Manual --> PR

    SM --> Conv
    PM --> Conv
    PR --> Conv

    Conv --> VMSS
    Conv --> VMPS
    Conv --> VMR

    VMSS --> VMAgent
    VMPS --> VMAgent
    VMAgent -->|"remote write"| VMSingle
    VMR --> VMAlert
    VMAlert -->|queries| VMSingle
    VMAlert -->|notifies| VMAMgr

    VMSingle -->|"Prometheus API :8428"| Grafana
    Vector -->|"jsonline :9428"| VLSingle
```

---

## Understanding the Two CRD Sets

This is the most important concept to understand. The cluster runs **two separate sets of CRDs** from two different organizations, and both are required.

### Set 1: Prometheus CRDs (`monitoring.coreos.com/v1`)

**Installed by**: `prometheus-operator-crds` Helm chart (from `prometheus-community`)

**What it provides**: Only the CRD definitions (the "vocabulary" that Kubernetes understands). No operator, no Prometheus server, no running pods.

| CRD | Kind | Purpose |
|-----|------|---------|
| `servicemonitors.monitoring.coreos.com` | ServiceMonitor | Declares "scrape metrics from this Service" |
| `podmonitors.monitoring.coreos.com` | PodMonitor | Declares "scrape metrics from these Pods" |
| `prometheusrules.monitoring.coreos.com` | PrometheusRule | Declares alerting/recording rules |
| `probes.monitoring.coreos.com` | Probe | Declares blackbox probing targets |
| `scrapeconfigs.monitoring.coreos.com` | ScrapeConfig | Declares custom scrape configurations |
| `alertmanagerconfigs.monitoring.coreos.com` | AlertmanagerConfig | Declares alert routing configuration |

**Who creates resources using these CRDs** (12+ files in this repo):

| Resource | File | Creator |
|----------|------|---------|
| `ServiceMonitor/microservices-api` | `configs/monitoring/servicemonitors/microservices.yaml` | Manual (platform team) |
| `ServiceMonitor/external-secrets` | `configs/monitoring/servicemonitors/external-secrets.yaml` | Manual (platform team) |
| `ServiceMonitor/tempo` | `configs/monitoring/servicemonitors/tempo.yaml` | Manual (platform team) |
| `PodMonitor/postgresql-auth-db` | `configs/monitoring/podmonitors/podmonitor-zalando-auth-db.yaml` | Manual (platform team) |
| `PodMonitor/postgresql-supporting-shared-db` | `configs/monitoring/podmonitors/podmonitor-zalando-supporting-shared-db.yaml` | Manual (platform team) |
| `PrometheusRule/postgres-alerts` | `configs/monitoring/prometheusrules/postgres-alerts.yaml` | Manual (platform team) |
| `PrometheusRule/postgres-backup-alerts` | `configs/monitoring/prometheusrules/postgres-backup-alerts.yaml` | Manual (platform team) |
| `PrometheusRule/pg-exporter-recording-rules` | `configs/monitoring/prometheusrules/pg-exporter-recording-rules.yaml` | Manual (platform team) |
| `ServiceMonitor` (valkey) | Created at runtime by Helm chart | Valkey chart (`serviceMonitor.enabled: true`) |
| `PodMonitor` (product-db, transaction-shared-db) | `configs/databases/clusters/*/monitoring/` | Manual (platform team) |
| `PrometheusRule` (SLO rules) | Created at runtime by Sloth | Sloth Operator (from PrometheusServiceLevel) |

**Why these CRDs are required**:
1. Third-party Helm charts (Valkey, CloudNativePG, etc.) only know how to create `ServiceMonitor` resources. They have no concept of VictoriaMetrics CRDs.
2. The Sloth SLO operator generates `PrometheusRule` resources. It does not support VMRule.
3. These are the de-facto standard for Kubernetes monitoring. Keeping them means compatibility with thousands of Helm charts.

### Set 2: VictoriaMetrics CRDs (`operator.victoriametrics.com/v1beta1` and `v1`)

**Installed by**: `victoria-metrics-operator` Helm chart (from VictoriaMetrics OCI registry)

**What it provides**: CRD definitions AND a running operator that manages the lifecycle of all VM components.

| CRD | Kind | Purpose |
|-----|------|---------|
| `vmsingles.operator.victoriametrics.com` | VMSingle | Single-node metrics storage |
| `vmagents.operator.victoriametrics.com` | VMAgent | Metrics scraping agent |
| `vmalerts.operator.victoriametrics.com` | VMAlert | Alerting/recording rule evaluator |
| `vmalertmanagers.operator.victoriametrics.com` | VMAlertmanager | Alert notification router |
| `vmservicescrapes.operator.victoriametrics.com` | VMServiceScrape | VM-native version of ServiceMonitor |
| `vmpodscrapes.operator.victoriametrics.com` | VMPodScrape | VM-native version of PodMonitor |
| `vmrules.operator.victoriametrics.com` | VMRule | VM-native version of PrometheusRule |
| `vlsingles.operator.victoriametrics.com` | VLSingle | Single-node log storage (**apiVersion: `v1`**, not `v1beta1`) |
| `vmclusters.operator.victoriametrics.com` | VMCluster | Distributed metrics storage (HA) |
| `vmauths.operator.victoriametrics.com` | VMAuth | Authentication/routing proxy |
| `vmusers.operator.victoriametrics.com` | VMUser | User access definitions |

**Who creates resources using these CRDs** (5 files in this repo):

| Resource | File | Purpose |
|----------|------|---------|
| `VMSingle/victoria-metrics` | `configs/monitoring/victoriametrics/vmsingle.yaml` | Metrics storage |
| `VMAgent/victoria-metrics` | `configs/monitoring/victoriametrics/vmagent.yaml` | Metrics scraping |
| `VMAlert/victoria-metrics` | `configs/monitoring/victoriametrics/vmalert.yaml` | Rule evaluation |
| `VMAlertmanager/victoria-metrics` | `configs/monitoring/victoriametrics/vmalertmanager.yaml` | Alert routing |
| `VLSingle/victoria-logs` | `configs/monitoring/victoriametrics/vlsingle.yaml` | Log storage |

Additionally, the VM Operator **auto-creates** VM resources by converting Prometheus CRDs:

| Source (Prometheus CRD) | Auto-created (VM CRD) |
|-------------------------|-----------------------|
| `ServiceMonitor/microservices-api` | `VMServiceScrape/microservices-api` |
| `PodMonitor/postgresql-auth-db` | `VMPodScrape/postgresql-auth-db` |
| `PrometheusRule/postgres-alerts` | `VMRule/postgres-alerts` |
| ...all other Prometheus resources | ...corresponding VM resources |

### Auto-Conversion Flow

```mermaid
flowchart LR
    subgraph step1 ["Step 1: CRD Exists"]
        CRD["prometheus-operator-crds<br/>registers ServiceMonitor CRD<br/>in Kubernetes API"]
    end

    subgraph step2 ["Step 2: Resource Created"]
        SM["ServiceMonitor/tempo<br/>apiVersion: monitoring.coreos.com/v1<br/>created by your YAML"]
    end

    subgraph step3 ["Step 3: VM Operator Watches"]
        VMOp["VM Operator detects new<br/>ServiceMonitor and creates<br/>VMServiceScrape/tempo"]
    end

    subgraph step4 ["Step 4: VMAgent Reads"]
        VMAgent["VMAgent discovers<br/>VMServiceScrape/tempo<br/>and starts scraping"]
    end

    CRD --> SM
    SM --> VMOp
    VMOp --> VMAgent
```

**Operator configuration** controlling this behavior (from `victoria-metrics-operator.yaml`):

```yaml
operator:
  # Auto-convert Prometheus CRDs (ServiceMonitor -> VMServiceScrape, etc.)
  disable_prometheus_converter: false
  # Delete converted VM objects when the original Prometheus objects are deleted
  enable_converter_ownership: true
```

### Why You Cannot Remove Either Set

| If you remove... | What breaks |
|------------------|-------------|
| Prometheus CRDs | Valkey chart fails (`no matches for kind "ServiceMonitor"`), Sloth fails, all your ServiceMonitor/PodMonitor/PrometheusRule YAML files fail to apply |
| VictoriaMetrics CRDs | VMSingle, VMAgent, VMAlert, VMAlertmanager, VLSingle all disappear. No metrics storage, no scraping, no alerting, no logs |

---

## Components

### prometheus-operator-crds

| Property | Value |
|----------|-------|
| **Chart** | `prometheus-community/prometheus-operator-crds` |
| **HelmRelease** | `kubernetes/infra/controllers/metrics/prometheus-operator-crds.yaml` |
| **Namespace** | monitoring |
| **What it installs** | Prometheus CRD definitions only (no operator, no pods) |
| **Depends on** | Nothing (deployed first) |

### victoria-metrics-operator

| Property | Value |
|----------|-------|
| **Chart** | `oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-operator` |
| **HelmRelease** | `kubernetes/infra/controllers/metrics/victoria-metrics-operator.yaml` |
| **Namespace** | monitoring |
| **What it installs** | VM Operator pod + VM CRD definitions |
| **Depends on** | `prometheus-operator-crds` (needs Prometheus CRDs to enable auto-conversion) |

Key configuration:

```yaml
operator:
  disable_prometheus_converter: false    # Enable auto-conversion
  enable_converter_ownership: true       # Cleanup converted objects on deletion
admissionWebhooks:
  enabled: false                         # Disabled for local dev simplicity
```

### VMSingle (Metrics Storage)

| Property | Value |
|----------|-------|
| **CRD** | `operator.victoriametrics.com/v1beta1 / VMSingle` |
| **Manifest** | `kubernetes/infra/configs/monitoring/victoriametrics/vmsingle.yaml` |
| **Service** | `vmsingle-victoria-metrics.monitoring.svc:8428` |
| **VMUI** | `http://vmsingle-victoria-metrics.monitoring.svc:8428/vmui` |
| **Prometheus API** | `http://vmsingle-victoria-metrics.monitoring.svc:8428/api/v1/query` |
| **Write API** | `http://vmsingle-victoria-metrics.monitoring.svc:8428/api/v1/write` |

Configuration:

```yaml
spec:
  retentionPeriod: "7d"
  removePvcAfterDelete: true
  port: "8428"
  storage:
    accessModes: [ReadWriteOnce]
    resources:
      requests:
        storage: 20Gi
  resources:
    requests: { cpu: 50m, memory: 256Mi }
    limits:   { cpu: 200m, memory: 512Mi }
  extraArgs:
    dedup.minScrapeInterval: "15s"
```

VMSingle is fully Prometheus API compatible. Grafana, PromQL, and any tool that queries Prometheus can query VMSingle without changes. VictoriaMetrics also supports [MetricsQL](https://docs.victoriametrics.com/metricsql/), a superset of PromQL with additional functions.

### VMAgent (Scraping)

| Property | Value |
|----------|-------|
| **CRD** | `operator.victoriametrics.com/v1beta1 / VMAgent` |
| **Manifest** | `kubernetes/infra/configs/monitoring/victoriametrics/vmagent.yaml` |
| **Service** | `vmagent-victoria-metrics.monitoring.svc:8429` |
| **Targets UI** | `http://vmagent-victoria-metrics.monitoring.svc:8429/targets` |

Configuration:

```yaml
spec:
  selectAllByDefault: true    # Discover scrape targets in ALL namespaces
  remoteWrite:
    - url: "http://vmsingle-victoria-metrics.monitoring.svc:8428/api/v1/write"
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits:   { cpu: 200m, memory: 256Mi }
```

VMAgent reads `VMServiceScrape` and `VMPodScrape` resources (including those auto-converted from Prometheus CRDs) and scrapes the targets. `selectAllByDefault: true` means it watches all namespaces without requiring specific label selectors.

### VMAlert (Rule Evaluation)

| Property | Value |
|----------|-------|
| **CRD** | `operator.victoriametrics.com/v1beta1 / VMAlert` |
| **Manifest** | `kubernetes/infra/configs/monitoring/victoriametrics/vmalert.yaml` |
| **Service** | `vmalert-victoria-metrics.monitoring.svc:8080` |
| **Rules UI** | `http://vmalert-victoria-metrics.monitoring.svc:8080/vmalert/groups` |

Configuration:

```yaml
spec:
  selectAllByDefault: true
  evaluationInterval: "15s"
  datasource:
    url: "http://vmsingle-victoria-metrics.monitoring.svc:8428"
  remoteWrite:
    url: "http://vmsingle-victoria-metrics.monitoring.svc:8428"
  remoteRead:
    url: "http://vmsingle-victoria-metrics.monitoring.svc:8428"
  notifier:
    url: "http://vmalertmanager-victoria-metrics.monitoring.svc:9093"
```

VMAlert reads `VMRule` resources (including those auto-converted from `PrometheusRule`) and evaluates them against VMSingle. This means:
- PostgreSQL alerts (`postgres-alerts.yaml`, `postgres-backup-alerts.yaml`)
- pg_exporter recording rules (`pg-exporter-recording-rules.yaml`)
- Sloth-generated SLO rules

All continue to work without any changes to the original `PrometheusRule` YAML files.

### VMAlertmanager (Alert Routing)

| Property | Value |
|----------|-------|
| **CRD** | `operator.victoriametrics.com/v1beta1 / VMAlertmanager` |
| **Manifest** | `kubernetes/infra/configs/monitoring/victoriametrics/vmalertmanager.yaml` |
| **Service** | `vmalertmanager-victoria-metrics.monitoring.svc:9093` |

Configuration:

```yaml
spec:
  selectAllByDefault: true
  replicaCount: 1
  configRawYaml: |
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'default'
    receivers:
      - name: 'default'
```

Currently configured with a `default` receiver (no-op). Add webhook, Slack, PagerDuty, or email receivers under `receivers` when alerting destinations are ready.

### VLSingle (Log Storage)

| Property | Value |
|----------|-------|
| **CRD** | `operator.victoriametrics.com/v1 / VLSingle` |
| **Manifest** | `kubernetes/infra/configs/monitoring/victoriametrics/vlsingle.yaml` |
| **Service** | `vlsingle-victoria-logs.monitoring.svc:9428` |
| **Ingest endpoint** | `/insert/jsonline` |
| **Query endpoint** | `/select/logsql/query` |

Configuration:

```yaml
spec:
  retentionPeriod: "7d"
  removePvcAfterDelete: true
  storage:
    resources:
      requests:
        storage: 20Gi
  resources:
    requests: { cpu: 20m, memory: 32Mi }
    limits:   { cpu: 100m, memory: 128Mi }
```

Log ingestion is handled by the cluster-wide **Vector Agent** (`kube-system/vector`) which ships Kubernetes logs to both Loki and VLSingle. See [VictoriaLogs docs](../logging/victorialogs.md) for Vector sink configuration.

---

## Flux Deployment Order

The dependency chain ensures components are installed in the correct order:

```mermaid
flowchart TD
    subgraph controllers ["controllers-local (Flux Kustomization)"]
        PromCRDs["prometheus-operator-crds"]
        VMOp["victoria-metrics-operator"]
        GrafanaOp["grafana-operator"]
        Sloth["sloth"]
        Jaeger["jaeger"]
        OTel["opentelemetry-collector"]
        Vector["vector"]
    end

    subgraph monitoring ["monitoring-local (Flux Kustomization)"]
        VMSingle_k["VMSingle"]
        VMAgent_k["VMAgent"]
        VMAlert_k["VMAlert"]
        VMAMgr_k["VMAlertmanager"]
        VLSingle_k["VLSingle"]
        SMs["ServiceMonitors"]
        PMs["PodMonitors"]
        PRs["PrometheusRules"]
        GrafanaCR["Grafana + Datasources"]
    end

    PromCRDs -->|"dependsOn"| VMOp
    VMOp -->|"dependsOn"| Sloth
    VMOp -->|"dependsOn"| Jaeger
    VMOp -->|"dependsOn"| OTel
    VMOp -->|"dependsOn"| Vector
    controllers -->|"dependsOn"| monitoring
```

**controllers-local** deploys operators and waits for all health checks:

```yaml
healthChecks:
  - name: prometheus-operator-crds    # CRDs registered in K8s API
  - name: victoria-metrics-operator   # VM Operator pod running
  - name: grafana-operator            # Grafana Operator pod running
  - name: sloth                       # Sloth Operator pod running
  # ... other operators
```

**monitoring-local** deploys configs (VMSingle, VMAgent, ServiceMonitors, Grafana, etc.) only after `controllers-local` is fully healthy.

**HelmRelease `dependsOn` chain**:

| HelmRelease | Depends on | Why |
|-------------|------------|-----|
| `prometheus-operator-crds` | Nothing | Must install CRDs first |
| `victoria-metrics-operator` | `prometheus-operator-crds` | Needs Prometheus CRDs to enable auto-conversion |
| `sloth` | `victoria-metrics-operator`, `grafana-operator` | Creates PrometheusRules that need CRDs registered |
| `jaeger` | `victoria-metrics-operator`, `grafana-operator` | Monitoring namespace dependency |
| `opentelemetry-collector` | `victoria-metrics-operator`, `grafana-operator` | Monitoring namespace dependency |
| `vector` | `victoria-metrics-operator` | Ships logs to VLSingle |

---

## Data Flow

### Metrics Flow

```mermaid
flowchart LR
    subgraph sources ["Metric Sources"]
        Apps["Microservices<br/>/metrics endpoint"]
        PG["PostgreSQL<br/>pg_exporter"]
        ESO["External Secrets<br/>/metrics"]
        TempoSvc["Tempo<br/>/metrics"]
    end

    subgraph promCRD ["Prometheus CRDs (your YAML)"]
        SM1["ServiceMonitor<br/>microservices-api"]
        PM1["PodMonitor<br/>postgresql-auth-db"]
        SM2["ServiceMonitor<br/>tempo"]
    end

    subgraph autoConv ["VM Operator auto-converts"]
        VMSS1["VMServiceScrape<br/>microservices-api"]
        VMPS1["VMPodScrape<br/>postgresql-auth-db"]
        VMSS2["VMServiceScrape<br/>tempo"]
    end

    subgraph vmStack ["VM Stack"]
        VMAgent_f["VMAgent"]
        VMSingle_f["VMSingle<br/>:8428"]
    end

    subgraph viz ["Visualization"]
        Grafana_f["Grafana<br/>:3000"]
    end

    SM1 --> VMSS1
    PM1 --> VMPS1
    SM2 --> VMSS2

    VMSS1 --> VMAgent_f
    VMPS1 --> VMAgent_f
    VMSS2 --> VMAgent_f

    VMAgent_f -->|"remote write"| VMSingle_f
    VMSingle_f -->|"PromQL / MetricsQL"| Grafana_f

    Apps -.->|scrape| VMAgent_f
    PG -.->|scrape| VMAgent_f
    ESO -.->|scrape| VMAgent_f
    TempoSvc -.->|scrape| VMAgent_f
```

### Alerting Flow

```mermaid
flowchart LR
    subgraph rules ["Rule Sources"]
        PR1["PrometheusRule<br/>postgres-alerts"]
        PR2["PrometheusRule<br/>postgres-backup-alerts"]
        PR3["PrometheusRule<br/>pg-exporter-recording-rules"]
        SlothPR["PrometheusRule<br/>SLO rules from Sloth"]
    end

    subgraph autoConv2 ["VM Operator auto-converts"]
        VMR1["VMRule<br/>postgres-alerts"]
        VMR2["VMRule<br/>postgres-backup-alerts"]
        VMR3["VMRule<br/>pg-exporter-recording-rules"]
        VMR4["VMRule<br/>SLO rules"]
    end

    subgraph eval ["Evaluation"]
        VMAlert_f["VMAlert<br/>evaluates every 15s"]
        VMSingle_f2["VMSingle<br/>datasource"]
    end

    subgraph notify ["Notification"]
        VMAMgr_f["VMAlertmanager<br/>routes alerts"]
    end

    PR1 --> VMR1
    PR2 --> VMR2
    PR3 --> VMR3
    SlothPR --> VMR4

    VMR1 --> VMAlert_f
    VMR2 --> VMAlert_f
    VMR3 --> VMAlert_f
    VMR4 --> VMAlert_f

    VMAlert_f <-->|"query metrics"| VMSingle_f2
    VMAlert_f -->|"firing alerts"| VMAMgr_f
```

### Logs Flow

```mermaid
flowchart LR
    Pods["Kubernetes Pods"] --> Vector["Vector Agent<br/>kube-system"]
    Vector -->|"jsonline :9428"| VLSingle_f["VLSingle<br/>victoria-logs"]
    Vector -->|"loki API :3100"| Loki["Loki"]
```

---

## Grafana Integration

The Grafana datasource (`configs/monitoring/grafana/datasource-prometheus.yaml`) points to VMSingle:

```yaml
spec:
  datasource:
    name: Prometheus
    type: prometheus
    uid: prometheus
    url: http://vmsingle-victoria-metrics.monitoring.svc:8428
```

Key points:
- The datasource **type remains `prometheus`** because VMSingle exposes a Prometheus-compatible API.
- The datasource **name and uid remain `Prometheus`** so all existing dashboard references continue to work.
- All 20+ Grafana dashboards work without any modification.
- PromQL queries work unchanged. MetricsQL (VictoriaMetrics superset) is also available.

---

## File Locations

```
kubernetes/
├── clusters/local/
│   ├── sources/
│   │   ├── oci/victoria-metrics-operator-oci.yaml  # OCI source for VM Operator chart
│   │   └── helm/prometheus-community.yaml          # Helm repo for Prometheus CRDs chart
│   └── controllers.yaml                            # Flux health checks (CRDs + operators)
│
├── infra/controllers/metrics/
│   ├── kustomization.yaml                          # Includes all metrics controllers
│   ├── prometheus-operator-crds.yaml               # HelmRelease: Prometheus CRDs only
│   ├── victoria-metrics-operator.yaml              # HelmRelease: VM Operator (depends on CRDs)
│   ├── grafana-operator.yaml                       # HelmRelease: Grafana Operator
│   ├── metrics-server.yaml                         # HelmRelease: Kubernetes Metrics Server
│   └── sloth-operator.yaml                         # HelmRelease: Sloth SLO Operator
│
├── infra/configs/monitoring/
│   ├── kustomization.yaml                          # Includes victoriametrics/ + all monitors
│   ├── victoriametrics/
│   │   ├── kustomization.yaml
│   │   ├── vmsingle.yaml                           # VMSingle CRD (metrics storage)
│   │   ├── vmagent.yaml                            # VMAgent CRD (scraping)
│   │   ├── vmalert.yaml                            # VMAlert CRD (rule evaluation)
│   │   ├── vmalertmanager.yaml                     # VMAlertmanager CRD (alert routing)
│   │   └── vlsingle.yaml                           # VLSingle CRD (log storage)
│   ├── servicemonitors/                            # Prometheus ServiceMonitor resources
│   ├── podmonitors/                                # Prometheus PodMonitor resources
│   ├── prometheusrules/                            # Prometheus PrometheusRule resources
│   └── grafana/
│       ├── datasource-prometheus.yaml              # Points to VMSingle :8428
│       └── dashboards/                             # 20+ GrafanaDashboard CRDs
│
└── infra/configs/databases/clusters/*/monitoring/  # Per-database PodMonitors/ServiceMonitors
```

---

## Verification and Operations

### Check Operator Status

```bash
# VM Operator pod
kubectl get pods -n monitoring -l app.kubernetes.io/name=victoria-metrics-operator

# All VM custom resources
kubectl get vmsingles,vmagents,vmalerts,vmalertmanagers,vlsingles -n monitoring

# Auto-converted resources (created by VM Operator from Prometheus CRDs)
kubectl get vmservicescrapes -A
kubectl get vmpodscrapes -A
kubectl get vmrules -A
```

### Check Prometheus CRDs

```bash
# Verify Prometheus CRDs are registered
kubectl api-resources --api-group=monitoring.coreos.com

# List all Prometheus resources
kubectl get servicemonitors -A
kubectl get podmonitors -A
kubectl get prometheusrules -A
```

### Check Scrape Targets

```bash
# Port-forward to VMAgent and open targets UI
kubectl port-forward -n monitoring svc/vmagent-victoria-metrics 8429:8429
# Open http://localhost:8429/targets
```

### Check Alerting Rules

```bash
# Port-forward to VMAlert and open rules UI
kubectl port-forward -n monitoring svc/vmalert-victoria-metrics 8080:8080
# Open http://localhost:8080/vmalert/groups
```

### Query Metrics

```bash
# Port-forward to VMSingle
kubectl port-forward -n monitoring svc/vmsingle-victoria-metrics 8428:8428

# Open VMUI (built-in query UI)
# http://localhost:8428/vmui

# Query via curl
curl -s 'http://localhost:8428/api/v1/query' \
  --data-urlencode 'query=up{job="microservices"}' | jq .
```

### Query Logs

```bash
# Port-forward to VLSingle
kubectl port-forward -n monitoring svc/vlsingle-victoria-logs 9428:9428

# Query logs with LogsQL
curl -s 'http://localhost:9428/select/logsql/query' \
  --data-urlencode 'query=_stream:{namespace="monitoring"}' \
  --data-urlencode 'limit=10' | jq .
```

### Quick Access (all port-forwards)

```bash
# Run the helper script to set up all port-forwards at once
make flux-ui
# Or: ./scripts/flux-ui.sh
```

Access URLs after running the script:

| Component | URL |
|-----------|-----|
| Grafana | http://localhost:3000 |
| VictoriaMetrics VMUI | http://localhost:8428/vmui |
| VictoriaLogs | http://localhost:9428 |
| Jaeger | http://localhost:16686 |

---

## Multi-Environment Strategy

The operator-managed approach scales cleanly across environments using the same CRD kinds with different values:

| | Local (Kind) | Staging | Production |
|--|--|--|--|
| **Metrics storage** | VMSingle (7d, 20Gi) | VMSingle (30d, 50Gi) | VMCluster (90d, 200Gi, HA) |
| **Scraping** | VMAgent (1 replica) | VMAgent (1 replica) | VMAgent (2 replicas) |
| **Alerting** | VMAlert + VMAlertmanager | VMAlert + VMAlertmanager | VMAlert + VMAlertmanager |
| **Access control** | None (local dev) | Basic | VMAuth + VMUser (RBAC + Ingress) |
| **Logs** | VLSingle (7d, 20Gi) | VLSingle (14d, 50Gi) | VLSingle (30d, 100Gi) |
| **Config method** | Kustomize base | Kustomize overlay | Kustomize overlay |

For production, `VMCluster` replaces `VMSingle` for horizontal scaling with separate `vminsert`, `vmselect`, and `vmstorage` components.

---

## Troubleshooting

### "no matches for kind ServiceMonitor"

**Symptom**: A HelmRelease (e.g., Valkey) fails with:
```
no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"
ensure CRDs are installed first
```

**Cause**: The `prometheus-operator-crds` chart is not installed or not yet ready.

**Fix**: Verify the CRDs HelmRelease:
```bash
kubectl get helmrelease -n monitoring prometheus-operator-crds
kubectl api-resources --api-group=monitoring.coreos.com
```

### "dependency victoria-metrics-operator is not ready"

**Symptom**: HelmReleases (Sloth, Jaeger, OTel Collector, Vector) are stuck waiting.

**Cause**: The VM Operator HelmRelease is still installing or failed.

**Fix**: Check the operator status:
```bash
kubectl get helmrelease -n monitoring victoria-metrics-operator
kubectl get pods -n monitoring -l app.kubernetes.io/name=victoria-metrics-operator
kubectl logs -n monitoring -l app.kubernetes.io/name=victoria-metrics-operator
```

### Auto-converted resources not appearing

**Symptom**: You created a `ServiceMonitor` but no `VMServiceScrape` was auto-created.

**Cause**: The VM Operator converter might be disabled or the operator hasn't reconciled yet.

**Fix**:
```bash
# Check operator logs for conversion activity
kubectl logs -n monitoring -l app.kubernetes.io/name=victoria-metrics-operator | grep -i convert

# Verify converter is enabled
kubectl get deployment -n monitoring -l app.kubernetes.io/name=victoria-metrics-operator \
  -o jsonpath='{.items[0].spec.template.spec.containers[0].env}' | jq .
```

### VMAgent not scraping targets

**Symptom**: Metrics are missing in Grafana.

**Fix**: Check VMAgent targets UI:
```bash
kubectl port-forward -n monitoring svc/vmagent-victoria-metrics 8429:8429
# Open http://localhost:8429/targets to see discovered targets and errors
```

### controllers-local stuck in "Reconciliation in progress"

**Symptom**: The Flux `controllers-local` Kustomization never becomes Ready.

**Cause**: One of the health checks is failing. Check which HelmRelease is not ready:
```bash
flux get helmreleases -A
kubectl get helmreleases -A -o wide
```

---

## References

- [VMAuth and vmauth (HTTP auth proxy)](vmauth.md) — vmauth binary, `auth.config`, VMAuth/VMUser CRs, Grafana vs API security (this repo has no VMAuth manifests yet).

- [VictoriaMetrics Operator Documentation](https://docs.victoriametrics.com/operator/)
- [VM Operator Quick Start](https://docs.victoriametrics.com/operator/quick-start/)
- [VM Operator Resources (all CRDs)](https://docs.victoriametrics.com/operator/resources/)
- [Prometheus Migration Guide](https://docs.victoriametrics.com/operator/integrations/prometheus/)
- [VictoriaMetrics Helm Charts](https://docs.victoriametrics.com/helm/)
- [VMSingle Documentation](https://docs.victoriametrics.com/operator/resources/vmsingle/)
- [VMAgent Documentation](https://docs.victoriametrics.com/operator/resources/vmagent/)
- [VMAlert Documentation](https://docs.victoriametrics.com/operator/resources/vmalert/)
- [VMAlertmanager Documentation](https://docs.victoriametrics.com/operator/resources/vmalertmanager/)
- [VLSingle Documentation](https://docs.victoriametrics.com/operator/resources/vlsingle/)
- [MetricsQL (PromQL superset)](https://docs.victoriametrics.com/metricsql/)
- [LogsQL (VictoriaLogs query language)](https://docs.victoriametrics.com/victorialogs/logsql/)
