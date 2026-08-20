# Grafana

Grafana is the unified visualization layer for all 4 observability pillars. It connects to VMSingle (metrics), Tempo (traces), VictoriaLogs (logs, LogsQL via plugin), Jaeger (traces), and Pyroscope (profiles) through configured datasources.

## Deployment

Grafana is deployed via the **Grafana Operator** using a `Grafana` CR:

- **CR**: `kubernetes/infra/configs/observability/grafana/grafana.yaml`
- **Image**: `grafana/grafana:13.2.0`
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
| VictoriaMetrics (Prometheus) | `prometheus` | No | same VMSingle URL | prometheus-TYPE alias — what `query: prometheus` datasource variables (Envoy Gateway, Temporal, cert-manager, VM self-boards) resolve against |
| VictoriaLogs | `victoriametrics-logs-datasource` | No | `vlsingle-victoria-logs:9428` | Log queries (LogsQL), trace correlation, [plugin](https://grafana.com/grafana/plugins/victoriametrics-logs-datasource/) |
| VictoriaTraces | `jaeger` | No | `vtsingle…:10428/select/jaeger` | Trace queries against the VictoriaTraces pilot (Jaeger query API) |
| Tempo | `tempo` | No | `tempo:3200` | Trace queries |
| Jaeger | `jaeger` | No | `jaeger:16686` | Trace search (alternative UI) |
| ClickHouse | `grafana-clickhouse-datasource` | No | `clickhouse…:9000` | SQL over `otel.otel_logs` / `otel.otel_traces` (RFC-0019) |
| Pyroscope | `grafana-pyroscope-datasource` | No | `pyroscope:4040` | Flamegraphs |

See [datasources.md](datasources.md) for metrics datasource details and Grafana Alerting UI notes.

**VictoriaLogs** is the sole log backend (logs ingested by Vector); use it for LogsQL queries, trace correlation, and the VM plugin workflow. See [datasources.md](datasources.md#logs-victorialogs).

**Datasource CRD files:**

```
kubernetes/infra/configs/observability/grafana/
├── datasource-victoriametrics.yaml             # VictoriaMetrics plugin (default metrics DS)
├── datasource-victoriametrics-prometheus.yaml  # prometheus-TYPE alias (dashboards with `query: prometheus` variables)
├── datasource-victorialogs.yaml                # VictoriaLogs plugin
├── datasource-victoriatraces.yaml              # VictoriaTraces via the Jaeger query API
├── datasource-tempo.yaml
├── datasource-jaeger.yaml
├── datasource-clickhouse.yaml                  # grafana-clickhouse-datasource (RFC-0019)
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

**31 `GrafanaDashboard` CRs across 9 folders**, delivered three ways —
`configMapRef` to a JSON vendored in this repo (preferred; auditable and
pinned), `configMapRef` to a ConfigMap the `grafana-dashboards` HelmRelease
renders (the RFC-0017 boards, owned in `duynhlab/helm-charts`), or `spec.url`
(grafana.com and legacy external-repo boards):

| Folder | Boards | Source |
|--------|--------|--------|
| Observability | Microservices Observability (~41 panels), Business KPIs, **Keycloak — Identity** (login/token KPIs), Order Saga & Payment — Cutover Baseline, Inventory Service — Stock Authority (both RFC-0021-era), **Temporal — Workflows & Activities** (SDK + Server rows), Tempo self-observability, K8s cluster overview, Vector | helm-charts ConfigMaps ×2 · in-repo JSON ×3 · `spec.url` ×3 |
| ClickHouse | Server/Engine, OTel logs+traces SQL, Service deep dive, OTel Overview / Logs Explorer / Trace Explorer | in-repo JSON ×6 (RFC-0019 / ADR-023) |
| API Gateway | Envoy Global, Envoy Clusters, Envoy Gateway Global, Resources Monitor, **Envoy Gateway — Edge Overview** | in-repo JSON ×4 vendored from `envoyproxy/gateway` v1.9.0 + ×1 hand-authored (golden signals / control plane / infra) |
| Databases | CloudNativePG, PG query performance, PG maintenance, PgDog | vendored/hand-rolled, external repo (`spec.url`) |
| GitOps | **cert-manager** (expiry/renewal, controller, ACME, workqueue — the visual surface for the CertManager* alerts) | in-repo JSON |
| VictoriaMetrics | VMSingle, VMAgent, VMAlert | grafana.com (`spec.url`) |
| Flux | Flux cluster, Flux control plane | fluxcd/flux2-monitoring-example (`spec.url`) |
| SLO | Sloth overview, Sloth detail | grafana.com (`spec.url`) |
| Cache | Redis/Valkey | external repo (`spec.url`) |

The **in-repo JSON** pattern (ClickHouse suite, Envoy Gateway, Temporal,
cert-manager, RFC-0021): the JSON lives next to the CRs under `dashboards/`,
a `configMapGenerator` entry in that directory's `kustomization.yaml` turns it
into a stable-named ConfigMap (`disableNameSuffixHash`), and the CR consumes it
via `configMapRef`. Boards whose datasource variable is `query: prometheus`
resolve against the prometheus-TYPE alias datasource, not the default VM plugin
DS. The local stack provisions file-based twins for the Observability, Gateway
and ClickHouse folders — see
[`local-stack/docs/observability.md`](../../../local-stack/docs/observability.md)
for the parity matrix and the recorded local divergences.

**Microservices Observability + Business KPIs** (RFC-0017): the JSONs live in
the [`duynhlab/helm-charts`](https://github.com/duynhlab/helm-charts) repo
(`charts/grafana-dashboards/dashboards/microservices/`). A `HelmRelease`
(`grafana-dashboards`, ns `monitoring`, chart via its own `OCIRepository`)
renders them as ConfigMaps and the `GrafanaDashboard` CRs consume them via
`configMapRef`, mapping `DS_PROMETHEUS` → `VictoriaMetrics`. **Edit the boards
in that repo and bump the chart** — the old
[`duynhlab/grafana-dashboards`](https://github.com/duynhlab/grafana-dashboards)
repo is deprecated (its remaining legacy boards — Tempo, K8s overview, the PG
trio, Redis — are still fetched via `spec.url` at their nested
`dashboard/<area>/<name>.json` paths until they migrate; **Temporal migrated
in-repo on 2026-08-18** after living unpinned on that repo's `main`).

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
    ├── kustomization.yaml               # CR list + configMapGenerator entries (stable names, no hash)
    ├── grafana-dashboard-main.yaml      # Microservices Observability (configMapRef → chart ConfigMap)
    ├── grafana-dashboard-business.yaml  # Business KPIs (configMapRef → chart ConfigMap)
    ├── grafana-dashboard-temporal.yaml  # Temporal (configMapRef → temporal.json, vendored in-repo)
    ├── grafana-dashboard-cert-manager.yaml  # cert-manager (configMapRef → cert-manager.json)
    ├── grafana-dashboard-clickhouse*.yaml   # ClickHouse suite (configMapRef → clickhouse-*.json)
    ├── grafana-dashboard-envoy-gateway.yaml # 4 CRs (configMapRef → envoy-gateway/*.json, vendored v1.9.0)
    ├── grafana-dashboard-cutover-baseline.yaml · grafana-dashboard-inventory.yaml
    ├── grafana-dashboard-*.yaml         # remaining boards (spec.url → grafana.com or legacy repo)
    ├── temporal.json · cert-manager.json · clickhouse-*.json · cutover-baseline.json · inventory.json
    └── envoy-gateway/*.json             # vendored envoyproxy/gateway v1.9.0 dashboards
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
_Last updated: 2026-08-18 — dashboard inventory rewritten to the real 31 CRs / 9 folders (it listed 3), the in-repo `configMapGenerator` pattern documented, Temporal vendored in-repo, cert-manager board added, and the datasource table/tree completed (prometheus alias, VictoriaTraces, ClickHouse)._
