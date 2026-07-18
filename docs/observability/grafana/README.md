# Grafana

Grafana is the unified visualization layer for all 4 observability pillars. It connects to VMSingle (metrics), Tempo (traces), VictoriaLogs (logs, LogsQL via plugin), Jaeger (traces), and Pyroscope (profiles) through configured datasources.

## Deployment

Grafana is deployed via the **Grafana Operator** using a `Grafana` CR:

- **CR**: `kubernetes/infra/configs/observability/grafana/grafana.yaml`
- **Image**: `grafana/grafana:13.1.0`
- **Namespace**: `monitoring`
- **Access**: anonymous login with Admin role (dev mode)

```bash
kubectl port-forward svc/grafana-service -n monitoring 3000:3000
# Open http://localhost:3000
```

## Security and access control

Grafana **organization roles**, **Teams**, and **anonymous** access are documented in [rbac-multi-team.md](rbac-multi-team.md). That page explains why anonymous `Admin` does not provide per-team separation and how this differs from **[VMAuth / vmauth](../metrics/victoriametrics.md#vmauth--vmauth-planned)** (HTTP proxy for VictoriaMetrics APIs—not the Grafana UI).

## Datasources

All datasources are managed as `GrafanaDatasource` CRDs (GitOps, no manual configuration):

| Datasource | Type | Default | URL | Purpose |
|------------|------|---------|-----|---------|
| VictoriaMetrics | `victoriametrics-metrics-datasource` | Yes | `vmsingle-victoria-metrics:8428` | Metrics (PromQL/MetricsQL), dashboards, Explore |
| VictoriaLogs | `victoriametrics-logs-datasource` | No | `vlsingle-victoria-logs:9428` | Log queries (LogsQL), trace correlation, [plugin](https://grafana.com/grafana/plugins/victoriametrics-logs-datasource/) |
| Tempo | `tempo` | No | `tempo:3200` | Trace queries |
| Jaeger | `jaeger` | No | `jaeger:16686` | Trace search (alternative UI) |
| Pyroscope | `grafana-pyroscope-datasource` | No | `pyroscope:4040` | Flamegraphs |

See [datasources.md](datasources.md) for metrics datasource details and Grafana Alerting UI notes.

**VictoriaLogs** is the sole log backend (logs ingested by Vector); use it for LogsQL queries, trace correlation, and the VM plugin workflow. See [datasources.md](datasources.md#logs-victorialogs).

**Datasource CRD files:**

```
kubernetes/infra/configs/observability/grafana/
├── datasource-victoriametrics.yaml    # VictoriaMetrics plugin (default metrics DS)
├── datasource-victorialogs.yaml       # VictoriaLogs plugin
├── datasource-tempo.yaml
├── datasource-jaeger.yaml
└── datasource-pyroscope.yaml
```

## Plugins

Plugins are installed via the `GF_INSTALL_PLUGINS` environment variable in the Grafana CR:

| Plugin | Version | Purpose |
|--------|---------|---------|
| `victoriametrics-metrics-datasource` | 0.25.2 | Native VictoriaMetrics datasource with MetricsQL support |
| `victoriametrics-logs-datasource` | 0.29.0 | VictoriaLogs datasource with LogsQL in Explore and dashboards |

The metrics plugin includes its Grafana 13 variable-editor fix. The logs plugin
now defaults to 50 result lines instead of 1000 to prevent heavy Explore
queries from freezing the browser; datasource owners can still raise the limit.

Both plugins must be listed in `allow_loading_unsigned_plugins` (comma-separated) since they are not signed by Grafana:

```yaml
spec:
  config:
    plugins:
      allow_loading_unsigned_plugins: victoriametrics-metrics-datasource,victoriametrics-logs-datasource
```

## Dashboards

Dashboards are managed as `GrafanaDashboard` CRDs or JSON ConfigMaps:

| Dashboard | Panels | Location |
|-----------|--------|----------|
| Microservices Observability | 8 rows / ~41 panels (RFC-0017 W3/W4) | [`duynhlab/helm-charts`](https://github.com/duynhlab/helm-charts) chart `grafana-dashboards` → ConfigMap → `GrafanaDashboard.configMapRef` |
| Microservices — Business KPIs | 10 domain rows (RFC-0017) | same chart (`business-otel.json`) → `configMapRef` |
| CloudNativePG Cluster Overview | Upstream CNPG cluster + operator metrics | `grafana-dashboards` repo, `dashboard/postgresql/cloudnative-pg-cluster.json` (`spec.url`) |

**Microservices Observability + Business KPIs** (RFC-0017): the JSONs live in
the [`duynhlab/helm-charts`](https://github.com/duynhlab/helm-charts) repo
(`charts/grafana-dashboards/dashboards/microservices/`). A `HelmRelease`
(`grafana-dashboards`, ns `monitoring`, chart via its own `OCIRepository`)
renders them as ConfigMaps and the `GrafanaDashboard` CRs consume them via
`configMapRef`, mapping `DS_PROMETHEUS` → `VictoriaMetrics`. **Edit the boards
in that repo and bump the chart** — the old
[`duynhlab/grafana-dashboards`](https://github.com/duynhlab/grafana-dashboards)
repo is deprecated (its remaining legacy boards are still fetched via
`spec.url` at their nested `dashboard/<area>/<name>.json` paths until they
migrate).

**CloudNativePG**: JSON is vendored from [cloudnative-pg/grafana-dashboards](https://github.com/cloudnative-pg/grafana-dashboards) (`charts/cluster/grafana-dashboard.json`), adapted for the VictoriaMetrics plugin (same pattern as other JSON dashboards). `GrafanaDashboard` maps `DS_PROMETHEUS` → `VictoriaMetrics`. Cluster DB metrics use `PodMonitor` resources under [`kubernetes/infra/configs/databases/clusters/`](../../../kubernetes/infra/configs/databases/clusters/) (e.g. `product-db/monitoring/`); the CNPG **operator** `PodMonitor` is created when `monitoring.podMonitorEnabled` is true on the [`cloudnative-pg` HelmRelease](../../../kubernetes/infra/controllers/databases/cloudnativepg-operator.yaml).


Dashboard documentation:
- [Dashboard Reference](dashboard-reference.md) -- per-panel queries and what they measure
- [Variables](variables.md) -- `$app`, `$namespace`, `$rate` and regex patterns

## Alerting UI

Grafana's **Alerting > Alert rules** page shows two types of rules:

1. **Grafana-managed rules** -- created in Grafana UI, stored in Grafana DB
2. **Data source-managed rules (read-only)** -- fetched from external systems via `/api/v1/rules`

For our setup, **rule evaluation** is always **VMAlert** (from `PrometheusRule` / VMRule in GitOps). What varies is whether **Grafana’s UI** lists those rules as read-only: the default metrics datasource is **`victoriametrics-metrics-datasource`**, which is tuned for **queries**, not the same **ruler** integration path as Grafana’s native **`prometheus`** datasource type. So the Alerting page may show **few or no** external rule groups even though VMAlert is healthy.

See **[Grafana Alerting and datasource types](datasources.md#grafana-alerting-and-datasource-types)** for why this happens, optional **`type: prometheus`** (same VMSingle URL) for read-only listing, and fallbacks (VMAlert UI, Karma, `kubectl`, API).

## Manifest Locations

```
kubernetes/infra/configs/observability/grafana/
├── grafana.yaml                       # Grafana CR (operator-managed)
├── datasource-victoriametrics.yaml    # VictoriaMetrics plugin (default metrics)
├── datasource-victorialogs.yaml       # VictoriaLogs plugin datasource
├── datasource-tempo.yaml
├── datasource-jaeger.yaml
├── datasource-pyroscope.yaml
├── dashboards-chart.yaml              # HelmRelease → helm-charts grafana-dashboards chart (RFC-0017 boards as ConfigMaps)
└── dashboards/
    ├── grafana-dashboard-main.yaml     # Microservices Observability (configMapRef → chart ConfigMap)
    ├── grafana-dashboard-business.yaml # Business KPIs (configMapRef → chart ConfigMap)
    └── grafana-dashboard-*.yaml        # legacy boards (spec.url → grafana-dashboards repo nested paths, or grafana.com)
```

## Related Documentation

- [RBAC and multi-team access](rbac-multi-team.md) -- Viewer/Editor/Admin, Teams, anonymous vs named users
- [VMAuth and vmauth](../metrics/victoriametrics.md#vmauth--vmauth-planned) -- API-layer auth for VictoriaMetrics (separate from Grafana UI)
- [Datasource Strategy](datasources.md) -- VictoriaMetrics plugin metrics DS
- [Dashboard Reference](dashboard-reference.md) -- panel-by-panel reference
- [Variables](variables.md) -- dashboard variable configuration
- [Alerting Strategy](../alerting/README.md) -- 2-layer alerting approach
- [Metrics](../metrics/README.md) -- RED methodology and metric definitions

---
_Last updated: 2026-07-16 — RFC-0017 boards now delivered by the helm-charts `grafana-dashboards` chart (`configMapRef`); Business KPIs board added; legacy-board source notes corrected._
