# VictoriaMetrics Operator Stack

This platform uses the **VictoriaMetrics Operator** to manage the metrics stack (and related VM CRs such as VLSingle) via Kubernetes CRDs. It replaces the previous `kube-prometheus-stack` (Prometheus server + Prometheus Operator) with a fully operator-managed setup that provides lower resource usage, Prometheus API compatibility, and consistent configuration across environments.

| | |
|---|---|
| **Operator** | `victoria-metrics-operator` (namespace `monitoring`) |
| **Metrics** | VMSingle `:8428`, VMAgent `:8429` |
| **Alerting** | VMAlert + VMAlertmanager |
| **Logs** | VLSingle `:9428` — ops: [victorialogs.md](../logging/victorialogs.md) (not duplicated here) |
| **Access control** | None (Kind) — [VMAuth planned](#vmauth--vmauth-planned) |
| **Dual CRDs** | `prometheus-operator-crds` + VM Operator auto-converter |

## Table of contents

1. [Architecture](#architecture)
2. [Understanding the Two CRD Sets](#understanding-the-two-crd-sets)
3. [Components](#components)
4. [Flux Deployment Order](#flux-deployment-order)
5. [Data Flow](#data-flow)
6. [Grafana Integration](#grafana-integration)
7. [File Locations](#file-locations)
8. [Verification and Operations](#verification-and-operations)
9. [Multi-Environment Strategy](#multi-environment-strategy)
10. [Troubleshooting](#troubleshooting)
11. [References](#references)

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
        VLSingle["VLSingle<br/>logs — see victorialogs.md"]
    end

    subgraph consumers ["Consumers"]
        Grafana["Grafana<br/>Dashboards + Queries"]
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

    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef edge fill:#2563eb,color:#fff,stroke:#1e3a8a;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef external fill:#64748b,color:#fff,stroke:#334155;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    classDef log fill:#d3f9d8,color:#111,stroke:#2f9e44;
    classDef trace fill:#c5f6fa,color:#111,stroke:#0c8599;
    classDef collector fill:#a5d8ff,color:#111,stroke:#1971c2;
    class PromCRDs,VMOp,Conv,Grafana platform;
    class SM,PM,PR,VMSS,VMPS,VMR data;
    class Valkey,Sloth,CNPG,Manual external;
    class VMAgent,VMSingle metric;
    class VMAlert,VMAMgr platform;
    class VLSingle log;
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
| `ServiceMonitor/external-secrets` | `configs/observability/metrics/servicemonitors/external-secrets.yaml` | Manual (platform team) |
| `ServiceMonitor/tempo` | `configs/observability/metrics/servicemonitors/tempo.yaml` | Manual (platform team) |
| `ServiceMonitor/kong` | `controllers/kong/helmrelease.yaml` (`serviceMonitor.enabled: true`) | Kong chart (scrapes the proxy status port `:8100`) |
| `ServiceMonitor/kube-apiserver` | `configs/observability/metrics/servicemonitors/kube-apiserver.yaml` | Manual (platform team) |
| `PrometheusRule` (PostgreSQL, many) | `configs/observability/metrics/prometheusrules/postgres/` (`cnpg/`, `cnpg-platform-db/`) | Manual (platform team) |
| `PrometheusRule/postgres-backup-alerts` | `configs/observability/metrics/prometheusrules/postgres/backup-alerts.yaml` | Manual (platform team) |
| `ServiceMonitor` (valkey) | Created at runtime by Helm chart | Valkey chart (`serviceMonitor.enabled: true`) |
| `PodMonitor` (CNPG per cluster) | `configs/databases/clusters/{platform-db,product-db}/monitoring/podmonitor.yaml` | Manual (platform team) |
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
| `vmnodescrapes.operator.victoriametrics.com` | VMNodeScrape | Scrapes node-level targets (kubelet / cAdvisor) |
| `vmrules.operator.victoriametrics.com` | VMRule | VM-native version of PrometheusRule |
| `vlsingles.operator.victoriametrics.com` | VLSingle | Single-node log storage (**apiVersion: `v1`**, not `v1beta1`) |
| `vtsingles.operator.victoriametrics.com` | VTSingle | Single-node trace storage (pilot, **apiVersion: `v1`**) |
| `vmclusters.operator.victoriametrics.com` | VMCluster | Distributed metrics storage (HA) |
| `vmauths.operator.victoriametrics.com` | VMAuth | Authentication/routing proxy |
| `vmusers.operator.victoriametrics.com` | VMUser | User access definitions |

**Who creates resources using these CRDs** (7 files in this repo):

| Resource | File | Purpose |
|----------|------|---------|
| `VMSingle/victoria-metrics` | `configs/observability/metrics/victoriametrics/vmsingle.yaml` | Metrics storage |
| `VMAgent/victoria-metrics` | `configs/observability/metrics/victoriametrics/vmagent.yaml` | Metrics scraping |
| `VMAlert/victoria-metrics` | `configs/observability/metrics/victoriametrics/vmalert.yaml` | Rule evaluation |
| `VMAlertmanager/victoria-metrics` | `configs/observability/metrics/victoriametrics/vmalertmanager.yaml` | Alert routing |
| `VLSingle/victoria-logs` | `configs/observability/logging/victorialogs/vlsingle.yaml` | Log storage |
| `VTSingle/victoria-traces` | `configs/observability/tracing/victoriatraces/vtsingle.yaml` | Trace storage (pilot) |
| `VMNodeScrape/kubelet-{cadvisor,volume-stats}` | `configs/observability/metrics/victoriametrics/vmnodescrape-kubelet.yaml` | Kubelet cAdvisor + volume-stats scraping (2 CRs) |

**VLSingle** (log storage) uses the same Operator but is documented in the [VictoriaLogs ops guide](../logging/victorialogs.md) — ingest paths, Vector, endpoints, and troubleshooting are not duplicated here.

Additionally, the VM Operator **auto-creates** VM resources by converting Prometheus CRDs:

| Source (Prometheus CRD) | Auto-created (VM CRD) |
|-------------------------|-----------------------|
| `ServiceMonitor/tempo` | `VMServiceScrape/tempo` |
| `PodMonitor` (CNPG per cluster, e.g. `platform-db`) | `VMPodScrape` per resource |
| `PrometheusRule` under `postgres/cnpg/`, `cnpg-platform-db/` | Corresponding `VMRule` per resource |
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

    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef edge fill:#2563eb,color:#fff,stroke:#1e3a8a;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef external fill:#64748b,color:#fff,stroke:#334155;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    classDef log fill:#d3f9d8,color:#111,stroke:#2f9e44;
    classDef trace fill:#c5f6fa,color:#111,stroke:#0c8599;
    classDef collector fill:#a5d8ff,color:#111,stroke:#1971c2;
    class CRD,SM data;
    class VMOp platform;
    class VMAgent metric;
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
| **Manifest** | `kubernetes/infra/configs/observability/metrics/victoriametrics/vmsingle.yaml` |
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
| **Manifest** | `kubernetes/infra/configs/observability/metrics/victoriametrics/vmagent.yaml` |
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
| **Manifest** | `kubernetes/infra/configs/observability/metrics/victoriametrics/vmalert.yaml` |
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
- PostgreSQL alerts (`prometheusrules/postgres/` — `cnpg/`, `cnpg-platform-db/`, `backup-alerts.yaml`)
- Sloth-generated SLO rules

All continue to work without any changes to the original `PrometheusRule` YAML files.

### VMAlertmanager (Alert Routing)

| Property | Value |
|----------|-------|
| **CRD** | `operator.victoriametrics.com/v1beta1 / VMAlertmanager` |
| **Manifest** | `kubernetes/infra/configs/observability/metrics/victoriametrics/vmalertmanager.yaml` |
| **Service** | `vmalertmanager-victoria-metrics.monitoring.svc:9093` |

Configuration:

```yaml
spec:
  selectAllByDefault: true
  replicaCount: 1
  configRawYaml: |
    global:
      resolve_timeout: 5m
      # Local/dev placeholder — a syntactically valid (non-delivering) webhook so
      # the config loads. The real webhook is injected out-of-band into OpenBAO.
      slack_api_url: 'https://hooks.slack.com/services/T00000000/B00000000/devLocalPlaceholderXXXXXXXX'
    route:
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'slack-default'
      routes:
        - receiver: 'slack-critical'
          matchers: [severity="critical"]
          continue: true
        - receiver: 'watchdog-null'
          matchers: [alertname="Watchdog"]
    inhibit_rules:
      - source_matchers: [severity="critical"]
        target_matchers: [severity="warning"]
        equal: ['alertname', 'namespace']
      - source_matchers: [alertname="KubeNodeNotReady"]
        target_matchers: [severity=~"warning|critical"]
        equal: ['node']
      - source_matchers: [alertname="VMServiceDown"]
        target_matchers: [severity="warning"]
        equal: ['job']
    receivers:
      - name: 'slack-default'     # → #alerts
        slack_configs: [{ channel: '#alerts', send_resolved: true }]
      - name: 'slack-critical'    # → #alerts-critical
        slack_configs: [{ channel: '#alerts-critical', send_resolved: true }]
      - name: 'watchdog-null'     # black-hole for the always-firing Watchdog
```

Slack **is** wired: a default route to `#alerts`, a `continue: true` branch that also
sends `severity="critical"` alerts to `#alerts-critical`, and a null receiver that
swallows the always-firing `Watchdog`. Three `inhibit_rules` suppress warning-level
noise once a related critical fires. The `slack_api_url` committed here is a
non-delivering **dev placeholder**; the real webhook is injected out-of-band into
OpenBAO (never committed to this public repo).

### VMAuth / vmauth (planned)

**Status:** CRDs are installed by the VictoriaMetrics Operator Helm chart; this repo does **not** ship `VMAuth` or `VMUser` manifests yet. Planned for production external API access (see [Multi-Environment Strategy](#multi-environment-strategy)).

**vmauth** is an HTTP reverse proxy from the VictoriaMetrics ecosystem. It **authorizes**, **routes**, and **load-balances** requests to VMSingle, VMAgent, VMCluster, VictoriaLogs, or any HTTP backend.

| Property | Typical value |
|----------|----------------|
| Default listen port | `8427` (override with `-httpListenAddr`) |
| Config | `-auth.config=/path/to/auth/config.yml` |
| Reload | `SIGHUP`, `/-/reload` (protect with `-reloadAuthKey` in production) |

Official docs: [vmauth](https://docs.victoriametrics.com/victoriametrics/vmauth/) · [Operator auth](https://docs.victoriametrics.com/operator/auth/).

#### Binary vs Operator CR

| Aspect | vmauth (process) | VMAuth + VMUser (Kubernetes CRs) |
|--------|------------------|----------------------------------|
| What it is | Single binary / container | CRs managed by VictoriaMetrics Operator |
| Config | YAML `auth.config` on disk or URL | Operator renders config from `VMAuth` + `VMUser` |
| Ingress | You wire Ingress to the Service yourself | Recommended: Ingress → **VMAuth** Service |
| When to use | VMs, bare metal, custom Helm | GitOps-first clusters (this repo) |

#### Homelab fit

- **Kind dev:** not deployed; Grafana datasources point at VMSingle/VLSingle ClusterIP directly.
- **Production (planned):** basic/bearer auth for external PromQL and remote-write; `url_map` routing to vminsert/vmselect when using **VMCluster** (Kind uses **VMSingle** today).
- **Skip in-cluster Grafana path:** adding VMAuth between Grafana and VMSingle only makes sense if you intentionally change datasource URLs — usually unnecessary for internal dev.
- Full upstream use cases: [vmauth use cases](https://docs.victoriametrics.com/victoriametrics/vmauth/#use-cases).

#### auth.config (minimal example)

```yaml
unauthorized_user:
  url_prefix: "http://vmsingle-victoria-metrics.monitoring.svc:8428/"
```

Production: protect `/-/reload`, `/metrics`, `/flags`, `/debug/pprof` — see [vmauth security](https://docs.victoriametrics.com/victoriametrics/vmauth/#security).

#### VMAuth + VMUser on Kubernetes

1. **VMAuth** selects **VMUser** objects (selectors) and can define **Ingress** to expose vmauth.
2. **VMUser** defines credentials and **targetRefs** (`static` `url:` or **crd** reference to `VMSingle`, `VMAgent`, VMCluster sub-resources).
3. The operator generates Secrets and builds the vmauth configuration.

CR fields: [VMAuth](https://docs.victoriametrics.com/operator/resources/vmauth/) · [VMUser](https://docs.victoriametrics.com/operator/resources/vmuser/).

#### Mapping to this repository

| Component | Manifest | Role if VMAuth added later |
|-----------|----------|----------------------------|
| VMSingle | `kubernetes/infra/configs/observability/metrics/victoriametrics/vmsingle.yaml` | PromQL `/api/v1/*` backend |
| VMAgent | `.../vmagent.yaml` | Scrape UI `/targets`, remote-write paths |
| VLSingle | `kubernetes/infra/configs/observability/logging/victorialogs/vlsingle.yaml` | Logs HTTP API `:9428` |
| Grafana | `kubernetes/infra/configs/observability/grafana/grafana.yaml` | Not replaced by VMAuth for in-cluster datasource URLs by default |
| Datasources | `.../grafana/datasource-*.yaml` | Point to in-cluster Services (e.g. `vmsingle-victoria-metrics:8428`) |

#### Grafana vs VMAuth (two security layers)

| Layer | What it protects | This repo (typical) |
|-------|------------------|---------------------|
| **Grafana** (org roles, Teams, folders) | **Grafana UI**, dashboards, datasource access | [rbac-multi-team.md](../grafana/rbac-multi-team.md) |
| **VMAuth / vmauth** | **HTTP APIs** (PromQL, remote write, VictoriaLogs) outside the Grafana→ClusterIP path | Ingress or direct API clients (planned) |

[VMAuth does not fix anonymous Grafana Admin](../grafana/rbac-multi-team.md).

#### Access paths

```mermaid
flowchart LR
    subgraph current ["Current — in-cluster Grafana"]
        browser["Browser<br/>port-forward"]
        grafana["Grafana pod"]
        vmSingleCur[("VMSingle ClusterIP")]
        browser --> grafana
        grafana -->|"datasource proxy"| vmSingleCur
    end

    subgraph planned ["Planned — external API client"]
        client["External client"]
        vmAuth["VMAuth :8427<br/>(planned)"]
        vmSinglePlanned[("VMSingle :8428")]
        client -.->|"planned: HTTPS + auth"| vmAuth
        vmAuth -.->|"planned: PromQL proxy"| vmSinglePlanned
    end

    classDef external fill:#64748b,color:#fff,stroke:#334155;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    classDef planned fill:#fff,color:#475569,stroke:#64748b,stroke-dasharray:5 5;
    class browser,client external;
    class grafana platform;
    class vmSingleCur,vmSinglePlanned metric;
    class vmAuth planned;
```

- Grafana secures the **UI**; VMAuth secures **direct HTTP access** (scripts, other clusters, public Ingress).
- Point Grafana datasources at VMAuth only if you want unified audit/extra auth — for Kind dev, direct VMSingle is simpler.

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

    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef edge fill:#2563eb,color:#fff,stroke:#1e3a8a;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef external fill:#64748b,color:#fff,stroke:#334155;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    classDef log fill:#d3f9d8,color:#111,stroke:#2f9e44;
    classDef trace fill:#c5f6fa,color:#111,stroke:#0c8599;
    classDef collector fill:#a5d8ff,color:#111,stroke:#1971c2;
    class PromCRDs,VMOp,GrafanaOp,Sloth,Jaeger,OTel platform;
    class Vector,VLSingle_k log;
    class VMSingle_k,VMAgent_k metric;
    class VMAlert_k,VMAMgr_k platform;
    class SMs,PMs,PRs data;
    class GrafanaCR platform;
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
        Apps["Microservices<br/>OTLP push (RFC-0014)"]
        PG["PostgreSQL<br/>CNPG built-in :9187"]
        ESO["External Secrets<br/>/metrics"]
        TempoSvc["Tempo<br/>/metrics"]
    end

    subgraph promCRD ["Prometheus CRDs (your YAML)"]
        PM1["PodMonitor<br/>CNPG per cluster"]
        SM2["ServiceMonitor<br/>tempo"]
    end

    subgraph autoConv ["VM Operator auto-converts"]
        VMPS1["VMPodScrape<br/>CNPG per cluster"]
        VMSS2["VMServiceScrape<br/>tempo"]
    end

    subgraph vmStack ["VM Stack"]
        VMAgent_f["VMAgent"]
        VMSingle_f["VMSingle<br/>:8428"]
    end

    subgraph viz ["Visualization"]
        Grafana_f["Grafana<br/>:3000"]
    end

    PM1 --> VMPS1
    SM2 --> VMSS2

    VMPS1 --> VMAgent_f
    VMSS2 --> VMAgent_f

    VMAgent_f -->|"remote write"| VMSingle_f
    VMSingle_f -->|"PromQL / MetricsQL"| Grafana_f

    Apps -->|"OTLP push :8429"| VMAgent_f
    PG -->|scrape| VMAgent_f
    ESO -->|scrape| VMAgent_f
    TempoSvc -->|scrape| VMAgent_f

    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef edge fill:#2563eb,color:#fff,stroke:#1e3a8a;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef external fill:#64748b,color:#fff,stroke:#334155;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    classDef log fill:#d3f9d8,color:#111,stroke:#2f9e44;
    classDef trace fill:#c5f6fa,color:#111,stroke:#0c8599;
    classDef collector fill:#a5d8ff,color:#111,stroke:#1971c2;
    class Apps service;
    class PG,ESO,TempoSvc external;
    class PM1,SM2,VMPS1,VMSS2 data;
    class VMAgent_f,VMSingle_f metric;
    class Grafana_f platform;
```

### Alerting Flow

```mermaid
flowchart LR
    subgraph rules ["Rule Sources"]
        PR1["PrometheusRule<br/>postgres/* (all CNPG)"]
        PR2["PrometheusRule<br/>postgres-backup-alerts"]
        PR3["PrometheusRule<br/>microservices/alerts + recording-rules"]
        SlothPR["PrometheusRule<br/>SLO rules from Sloth"]
    end

    subgraph autoConv2 ["VM Operator auto-converts"]
        VMR1["VMRule<br/>postgres/* (all CNPG)"]
        VMR2["VMRule<br/>postgres-backup-alerts"]
        VMR3["VMRule<br/>microservices"]
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

    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef edge fill:#2563eb,color:#fff,stroke:#1e3a8a;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef external fill:#64748b,color:#fff,stroke:#334155;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    classDef log fill:#d3f9d8,color:#111,stroke:#2f9e44;
    classDef trace fill:#c5f6fa,color:#111,stroke:#0c8599;
    classDef collector fill:#a5d8ff,color:#111,stroke:#1971c2;
    class PR1,PR2,PR3,SlothPR,VMR1,VMR2,VMR3,VMR4 data;
    class VMSingle_f2 metric;
    class VMAlert_f,VMAMgr_f platform;
```

Log ingest and query paths: [VictoriaLogs ops guide](../logging/victorialogs.md).

---

## Grafana Integration

The Grafana metrics datasource ([`datasource-victoriametrics.yaml`](../../../kubernetes/infra/configs/observability/grafana/datasource-victoriametrics.yaml)) uses the **VictoriaMetrics plugin** (`victoriametrics-metrics-datasource`) and points to VMSingle:

```yaml
spec:
  datasource:
    name: VictoriaMetrics
    type: victoriametrics-metrics-datasource
    uid: victoriametrics
    url: http://vmsingle-victoria-metrics.monitoring.svc:8428
```

Key points:
- VMSingle exposes a Prometheus-compatible HTTP API; the plugin adds MetricsQL and VMUI integration from Grafana.
- Dashboards may still use the variable name `DS_PROMETHEUS` mapped to this datasource in `GrafanaDashboard` CRDs.
- PromQL-compatible queries work; MetricsQL extensions are available. See [Grafana datasources](../grafana/datasources.md).

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
├── infra/configs/observability/
│   ├── kustomization.yaml                          # Includes victoriametrics/ + all monitors
│   ├── victoriametrics/
│   │   ├── kustomization.yaml
│   │   ├── vmsingle.yaml                           # VMSingle CRD (metrics storage)
│   │   ├── vmagent.yaml                            # VMAgent CRD (scraping)
│   │   ├── vmalert.yaml                            # VMAlert CRD (rule evaluation)
│   │   ├── vmalertmanager.yaml                     # VMAlertmanager CRD (alert routing)
│   │   └── vmnodescrape-kubelet.yaml               # VMNodeScrape (kubelet cAdvisor)
│   ├── logging/victorialogs/
│   │   └── vlsingle.yaml                           # VLSingle CRD (log storage)
│   ├── servicemonitors/                            # Prometheus ServiceMonitor resources
│   ├── podmonitors/                                # Prometheus PodMonitor resources
│   ├── prometheusrules/                            # Prometheus PrometheusRule resources
│   └── grafana/
│       ├── datasource-victoriametrics.yaml         # VM plugin → VMSingle :8428
│       └── dashboards/                             # GrafanaDashboard CRDs + JSON
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
  --data-urlencode 'query=go_goroutine_count{app!=""}' | jq .   # app liveness: OTLP push has no up{}; see D-4 heartbeat
```

Log queries and VLSingle verification: [victorialogs.md](../logging/victorialogs.md).

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
| VictoriaLogs | http://localhost:9428 — query/ops: [victorialogs.md](../logging/victorialogs.md) |
| Jaeger | http://localhost:16686 |

---

## Multi-Environment Strategy

The operator-managed approach scales cleanly across environments using the same CRD kinds with different values:

| | Local (Kind) | Staging | Production |
|--|--|--|--|
| **Metrics storage** | VMSingle (7d, 20Gi) | VMSingle (30d, 50Gi) | VMCluster (90d, 200Gi, HA) |
| **Scraping** | VMAgent (1 replica) | VMAgent (1 replica) | VMAgent (2 replicas) |
| **Alerting** | VMAlert + VMAlertmanager | VMAlert + VMAlertmanager | VMAlert + VMAlertmanager |
| **Access control** | None (local dev) | Basic | [VMAuth + VMUser](#vmauth--vmauth-planned) (RBAC + Ingress) |
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

- [vmauth](https://docs.victoriametrics.com/victoriametrics/vmauth/) · [Operator auth](https://docs.victoriametrics.com/operator/auth/) · [VMAuth CRD](https://docs.victoriametrics.com/operator/resources/vmauth/) · [VMUser CRD](https://docs.victoriametrics.com/operator/resources/vmuser/)
- [VictoriaLogs ops guide](../logging/victorialogs.md) — VLSingle ingest, Vector, LogsQL (not duplicated here)
- [Grafana multi-team RBAC](../grafana/rbac-multi-team.md)
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

---

_Last updated: 2026-07-18 — Merge vmauth into this page; trim duplicated VLSingle/logs content (see victorialogs.md)._
