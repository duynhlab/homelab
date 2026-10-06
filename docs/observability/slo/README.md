# SLO System Documentation

## Overview

The SLO (Service Level Objective) system provides automated monitoring and alerting for all microservices using [Sloth](https://sloth.dev) **v0.16.0**, following Google SRE best practices with multi-window multi-burn-rate alerts.

> **Where are the `PrometheusServiceLevel` manifests?** Mostly not in this repo
> — and that surprises everyone once. The **external `slo` chart**
> ([`duynhlab/helm-charts/charts/slo`](https://github.com/duynhlab/helm-charts/tree/main/charts/slo))
> renders one per service from a `<service>-slo` HelmRelease, which the five
> domain ResourceSets emit for every service they template. So
> `grep -r PrometheusServiceLevel` in homelab finds only the two hand-written
> ones (inventory, Keycloak) while the cluster has eleven. To see the real specs,
> read them from the cluster: `kubectl get psl -A`.

**Key Features**:
- Automated SLO generation via the `slo` Helm chart (one `<service>-slo` HelmRelease per service)
- Kubernetes-native using PrometheusServiceLevel CRDs
- Automatic PrometheusRule generation via Sloth Operator
- Multi-window multi-burn-rate alerts (Google SRE pattern)
- Error budget tracking
- Grafana dashboards (auto-deployed)
- **Built-in Sloth Web UI** at [http://slo.duynh.me](http://slo.duynh.me) — service/SLO browser, live SLI charts, burn-rate views, alert state filtering (new in v0.16.0)
- **K8s transformer plugins** — Sloth now renders the prometheus-operator `PrometheusRule` via a dynamic `unstructured` transformer plugin (`sloth.dev/k8stransform/prom-operator-prometheus-rule/v1`), and one SLO can emit multiple K8s objects (new in v0.16.0)

## Architecture

Full metrics and alerting topology (converter, VMAgent, VMSingle, VMAlert): see **[VictoriaMetrics Operator stack](../metrics/victoriametrics.md)**.

```mermaid
flowchart TD
    subgraph helmChart ["slo Helm chart"]
        HR["HelmRelease &lt;service&gt;-slo<br/>(domain ResourceSets)"] -->|render| PSL["PrometheusServiceLevel<br/>9 services x 2 HTTP SLOs<br/>ns: monitoring"]
        HR -->|render| BURN["PrometheusRule &lt;service&gt;-slo-burn<br/>burn-rate alerts, minEvents guard"]
    end

    subgraph handWritten ["homelab manifests (Kustomize)"]
        GRPC["PrometheusServiceLevel<br/>inventory-grpc + keycloak-login<br/>2 SLOs each, ns: monitoring"]
    end

    PSL -->|watch| Sloth["Sloth Operator v0.16.0"]
    GRPC -->|watch| Sloth
    Sloth -->|generate via<br/>k8s transformer plugin| PR["PrometheusRules<br/>(recording + alerting)"]
    PR -->|convert| VMR["VMRule"]
    BURN -->|convert| VMR
    VMR --> VMA["VMAlert"]
    VMA -->|queries| VMS["VMSingle"]
    VMA -->|notifies| VMAM["VMAlertmanager"]
    VMS -->|Prometheus-compatible API| Grafana["Grafana Dashboards"]
    VMS -->|Prometheus-compatible API| SlothUI["Sloth Web UI<br/>slo.duynh.me"]

    App["Service SDK<br/>(OTLP push)"] --> OC["otel-collector"]
    OC --> VMAgent["VMAgent<br/>(OTLP ingest + relabel)"]
    VMAgent -->|remote write| VMS
    classDef service fill:#cffafe,color:#164e63,stroke:#0891b2;
    classDef data fill:#dcfce7,color:#14532d,stroke:#16a34a;
    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    classDef collector fill:#e0f2fe,color:#0c4a6e,stroke:#1971c2;
    classDef platform fill:#ede9fe,color:#4c1d95,stroke:#7c3aed;
    class App service;
    class OC collector;
    class PSL,GRPC,PR,VMR,BURN data;
    class VMS,VMAgent metric;
    class HR,Sloth,VMA,VMAM,Grafana,SlothUI platform;
```

**How it works**:
1. Each domain ResourceSet emits a `<service>-slo` HelmRelease next to the
   service's workload HelmRelease (not written per service by hand; a gRPC-only
   service opts out with `slo_disabled`)
2. The `slo` Helm chart renders a `PrometheusServiceLevel` CRD **into the
   `monitoring` namespace**, plus a `PrometheusRule` of burn-rate alerts. That namespace is load-bearing: the Sloth
   controller runs with `values.sloth.namespace: "monitoring"`, so a
   `PrometheusServiceLevel` anywhere else is **silently ignored** — no error
   event, no rules, no SLO. inventory's gRPC SLOs are hand-written into the same
   namespace for that reason
3. Sloth Operator watches the CRD and generates PrometheusRules
4. The VictoriaMetrics Operator converts those rules to VMRules; VMAlert evaluates PromQL-compatible rules against VMSingle, tracks error budgets, and sends alerts to VMAlertmanager
5. The 10 Go services and 2 workers push metrics via OTLP (SDK → otel-collector → VMAgent OTLP ingest); VMAgent relabels the OTLP resource attributes (`service_name`→`app`, `k8s_namespace_name`→`namespace`) and remote-writes to VMSingle. There is no `/metrics` scrape for the app services anymore — VMAgent's ServiceMonitor/VMServiceScrape path now covers only infra exporters (postgres, kube-state, cAdvisor, etc.)
6. The standalone **Sloth UI** Deployment (separate from the controller) reads SLI/error-budget series back from VMSingle to render its dashboards

## SLO Definitions

Each HTTP service has **2 SLOs** with default targets (overridable per service through the `slo` chart values):

| SLO | Objective | SLI | Alert |
|---|---|---|---|
| **Availability** | 99.5% | Non-5xx request ratio | `{Service}HighErrorRate` |
| **Latency** | 95.0% | Requests < 500ms ratio | `{Service}HighLatency` |

inventory is gRPC-only and has its own two, on `rpc_server_call_duration_seconds`:

| SLO | Objective | SLI | Alert |
|---|---|---|---|
| **grpc-availability** | 99.9% | Calls answered without a server fault (business refusals excluded) | `InventoryGrpcHighErrorRate` |
| **reserve-latency** | 95.0% | `Reserve` calls < 250ms | `InventoryReserveHighLatency` |

### SLI Queries (PromQL)

Chart-rendered SLIs all use the same base metric `http_server_request_duration_seconds` (OTel semconv) with Sloth's `{{.window}}` template:

**Availability** (5xx only):
```promql
# errorQuery
sum(rate(http_server_request_duration_seconds_count{app="<service>", namespace="<ns>", http_response_status_code=~"5.."}[{{.window}}]))
# totalQuery
sum(rate(http_server_request_duration_seconds_count{app="<service>", namespace="<ns>"}[{{.window}}]))
```

**Latency** (total - fast = slow):
```promql
# errorQuery (requests slower than threshold)
sum(rate(http_server_request_duration_seconds_count{...}[{{.window}}])) - sum(rate(http_server_request_duration_seconds_bucket{..., le="0.5"}[{{.window}}]))
# totalQuery
sum(rate(http_server_request_duration_seconds_count{...}[{{.window}}]))
```

### Query Labels

| Label | Source | Example |
|---|---|---|
| `app` | OTLP resource attr `service_name`, VMAgent relabel → `app` | `user` |
| `namespace` | OTLP resource attr `k8s_namespace_name`, VMAgent relabel → `namespace` | `user` |
| `http_response_status_code` | Application metric (OTel semconv) | `200`, `404`, `500` |

## SLO Targets

The nine HTTP services use the same default targets for consistency:

| SLO Type | 30-day Target | Error Budget | Rationale |
|---|---|---|---|
| Availability | 99.5% | 3.6 hours/month | Industry standard for production APIs |
| Latency | 95% < 500ms | 5% slow requests | Users notice delays > 500ms |

inventory is stricter, from RFC-0021's own numbers rather than the chart defaults:

| SLO Type | 30-day Target | Error Budget | Rationale |
|---|---|---|---|
| grpc-availability | 99.9% | ~43 min/month | It is the synchronous dependency inside the 99.9% checkout confirm handoff, so it cannot have a looser target than the flow it gates. Checkout fails **closed**: one server fault is one 503 to a shopper |
| reserve-latency | 95% < 250ms | 5% slow `Reserve` calls | East-west budget, not an edge one — `Reserve` runs inside a shopper's confirm request and composes with its timeout |

Per-service overrides go in that service's `<service>-slo` HelmRelease values
(`slo` chart):
```yaml
availability:
  objective: 99.9  # stricter for critical service
```

## Services

All ten services are SLO-enabled, plus Keycloak. Nine services take the
`slo` chart's HTTP SLOs; inventory and Keycloak are the exceptions, and the
reasons are in their rows.

| Service | Namespace | SLOs | SLI metric | Source |
|---|---|---|---|---|
| user | user | 2 | HTTP | `slo` chart, `user-slo` HelmRelease |
| product | product | 2 | HTTP | `slo` chart, `product-slo` HelmRelease |
| cart | cart | 2 | HTTP | `slo` chart, `cart-slo` HelmRelease |
| order | order | 2 | HTTP | `slo` chart, `order-slo` HelmRelease |
| review | review | 2 | HTTP | `slo` chart, `review-slo` HelmRelease |
| notification | notification | 2 | HTTP | `slo` chart, `notification-slo` HelmRelease |
| shipping | shipping | 2 | HTTP | `slo` chart, `shipping-slo` HelmRelease |
| checkout | checkout | 2 | HTTP | `slo` chart, `checkout-slo` HelmRelease |
| payment | payment | 2 | HTTP | `slo` chart, `payment-slo` HelmRelease |
| **inventory** | inventory | **2** | **gRPC** | hand-written [`inventory-grpc-slo.yaml`](../../../kubernetes/infra/configs/observability/sloth/inventory-grpc-slo.yaml); chart SLO off via `slo_disabled` |
| **keycloak** | identity | **2** | **Keycloak events + HTTP** | hand-written [`keycloak-login-slo.yaml`](../../../kubernetes/infra/configs/observability/sloth/keycloak-login-slo.yaml); Keycloak is platform infra, not a chart-rendered service |

**Total: 22 SLOs → 44 burn-rate alerts** — 18 chart-rendered (9 services × 2)
through the five domain ResourceSets, plus inventory's 2 and Keycloak's 2
hand-written ones. (The chart's third SLO, a 4xx+5xx error rate, was dropped in
`mop` 0.19.0 and is not part of the `slo` chart.)

Until 2026-08-06 the count was 33 (11 × 3), but inventory's three were **dead**:
the chart builds HTTP SLIs and inventory serves gRPC only (no Kong route,
health/ready not instrumented), so `http_server_request_duration_seconds{app="inventory"}`
had no series at all — a 0/0 SLI, no error budget, and a burn-rate alert that
could never fire on the platform's only stock authority. They were replaced by
two gRPC SLOs with RFC-0021's targets (availability 99.9%, `Reserve` p95 <
250 ms). The chart's third SLO (4xx+5xx) has no honest gRPC analogue: the
closest thing is a business refusal, which already has precise named alerts in
[`checkout-availability.yaml`](../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/checkout-availability.yaml).

**Adding a gRPC-only service:** set `slo_disabled: "true"` on its
`ResourceSetInputProvider` and add a hand-written `PrometheusServiceLevel` in
`monitoring` next to inventory's. The opt-out is deliberately an opt-**out**:
the ResourceSet guard is truthiness-based, so an input of `"false"` would read
as true.

## SLO metrics (PromQL on VictoriaMetrics)

Sloth still emits **PrometheusRule** CRDs; evaluation runs in **VMAlert**, and time series live in **VMSingle**. Queries remain PromQL-compatible (Grafana uses the VictoriaMetrics datasource against the same backend). Example recording-series names from Sloth:

```promql
# Error rate over multiple windows
slo:sli_error:ratio_rate5m{sloth_service="auth", sloth_slo="availability"}
slo:sli_error:ratio_rate30m{sloth_service="auth", sloth_slo="availability"}
slo:sli_error:ratio_rate1h{sloth_service="auth", sloth_slo="availability"}
slo:sli_error:ratio_rate6h{sloth_service="auth", sloth_slo="availability"}

# Error budget remaining
slo:error_budget_remaining:ratio{sloth_service="auth", sloth_slo="availability"}

# Current burn rate
slo:current_burn_rate:ratio{sloth_service="auth", sloth_slo="availability"}
```

## Sloth Web UI (v0.16.0)

The `sloth server` sub-command ships a built-in read-only web UI. We run it as a separate Deployment in `monitoring` (the upstream Helm chart only deploys the controller) and expose it through the edge (HTTPRoute).

**URL**: [http://slo.duynh.me](http://slo.duynh.me)

Features:

- Service listing + free-text search
- SLO listing — filter by service, by alert firing, by burn-rate-over-budget, by budget consumed in period
- SLO detail page — current stats, alert state, SLI ratio chart, error-budget burn-in-period chart
- Grouped SLO support (labels)
- Sortable service list (name / alert status)

**Backend**: queries the same VMSingle (`http://vmsingle-victoria-metrics.monitoring.svc:8428`) as VMAlert and Grafana — VictoriaMetrics' Prometheus-compatible API is fully supported. The UI itself is stateless; restart-safe.

**Manifest**: [`kubernetes/infra/configs/observability/sloth/sloth-ui.yaml`](../../../kubernetes/infra/configs/observability/sloth/sloth-ui.yaml). Image tag is pinned alongside the controller HelmRelease — bump both together. The Deployment ships at **0 replicas** — SLO rules are generated by the controller and read in Grafana, so the UI is optional browsing; scale it to 1 (`kubectl scale deploy/sloth-ui -n monitoring --replicas=1`) when you want the interactive view.

**Local DNS**: add `127.0.0.1 slo.duynh.me` to `/etc/hosts` (see [main README access points](../../../README.md#local-access)).

## Grafana Dashboards

Auto-deployed via Grafana Operator:

- **Sloth SLO Overview** (ID: 14643) -- high-level summary of all SLOs
- **Sloth SLO Detailed** (ID: 14348) -- per-service SLO metrics and error budgets

Access: http://grafana.duynh.me (folder: SLO).

The Grafana dashboards and the Sloth UI are complementary: Grafana for long-form, customizable panels and cross-stack correlation; Sloth UI for the canonical SLO/error-budget view straight from upstream.

## Documentation

- **[Fundamentals](./fundamentals.md)** -- SLA / SLO / SLI / Error Budget / Burn Rate primer (read this first)
- **[Getting Started](./getting_started.md)** -- Enable SLOs for a service
- **[Burn-Rate Alerts](../alerting/slo-burn-rate-alerts.md)** -- Multi-window multi-burn-rate alert configuration (lives under `alerting/`)
- **[Error Budget Policy](./error_budget_policy.md)** -- Budget management guidelines
- **[Annotation-Driven Controller](./annotation-driven-slo-controller.md)** -- Future approach for large-scale SLO automation

### Manifests

- SLO chart: [`duynhlab/helm-charts/charts/slo`](https://github.com/duynhlab/helm-charts/tree/main/charts/slo) (`PrometheusServiceLevel` + burn-rate `PrometheusRule`)
- Hand-written SLOs (the only `PrometheusServiceLevel`s in this repo): `kubernetes/infra/configs/observability/sloth/inventory-grpc-slo.yaml`, `keycloak-login-slo.yaml`
- Sloth Operator (controller): `kubernetes/infra/controllers/metrics/sloth-operator.yaml`
- Sloth Web UI (Deployment + Service + PodMonitor): `kubernetes/infra/configs/observability/sloth/sloth-ui.yaml`
- Sloth UI HTTPRoute: `kubernetes/infra/configs/envoy-gateway/routes/monitoring.yaml` (`slo.duynh.me`)
- OTLP metrics pipeline (app services push, no scrape): `kubernetes/infra/controllers/tracing/otel-collector/otel-collector.yaml`

### External References

- [Sloth Documentation](https://sloth.dev/)
- [Sloth v0.16.0 release notes](https://github.com/slok/sloth/releases/tag/v0.16.0) -- Web UI + K8s transformer plugins
- [Sloth `server` command source](https://github.com/slok/sloth/blob/main/cmd/sloth/commands/server.go) -- all CLI flags for the UI (Prometheus address, basic auth, mTLS, custom headers, cache refresh)
- [Google SRE Book -- SLOs](https://sre.google/sre-book/service-level-objectives/)
- [Google SRE Workbook -- Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)

---
_Last updated: 2026-10-06 — SLOs come from the `slo` chart (`<service>-slo` HelmReleases) instead of `mop`; counts corrected to 22 SLOs / 44 alerts (two chart SLOs per service since `mop` 0.19.0), and the retired `auth` row removed. Earlier: 2026-09-30 — counts corrected to 31 SLOs / 62 alerts (9 chart services). Earlier: 2026-08-20 — Keycloak's 2 hand-written identity SLOs added (34 SLOs / 68 burn-rate alerts)_
