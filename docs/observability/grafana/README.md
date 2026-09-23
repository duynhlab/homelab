# Grafana

Grafana is the unified visualization layer for all 4 observability pillars. It connects to VMSingle (metrics), VictoriaTraces (traces, via its Jaeger-compatible query API — ADR-058), VictoriaLogs (logs, LogsQL via plugin), ClickHouse (long-retention SQL), and Pyroscope (profiles) through configured datasources.

## Deployment

Grafana is deployed via the **Grafana Operator** using a `Grafana` CR:

- **CR**: `kubernetes/infra/configs/observability/grafana/grafana.yaml`
- **Image**: `grafana/grafana:13.2.0`
- **Namespace**: `monitoring`
- **Access**: **staff SSO** ([ADR-062](../../proposals/adr/ADR-062-staff-groups-sso/)) — "Sign in with Keycloak" at https://grafana.duynh.me; the staff realm's `groups` claim maps `infra-team`→Admin, `sre-team`→Editor, else Viewer. Anonymous access remains, as read-only **Viewer**; the user/password form is hidden.

```bash
kubectl port-forward svc/grafana-service -n monitoring 3000:3000
# Open http://localhost:3000 — anonymous Viewer only. The Keycloak sign-in
# does NOT work over a port-forward: server.root_url pins the OAuth
# redirect to https://grafana.duynh.me, so use the edge URL to log in.
```

## Security and access control

Humans authenticate through the staff realm (ADR-062): group membership in Keycloak decides the org role, no per-tool accounts. One machine identity exists besides that: a `GrafanaServiceAccount` (`grafana-service-account-mcp.yaml`) with role **Viewer**, whose operator-minted token (Secret `grafana-mcp-token`) is consumed by the [Grafana MCP server](../../platform/mcp-servers.md#4-grafana-mcp). Since ADR-062 that token is an *equal* of anonymous access (both Viewer), not a narrowing of an anonymous Admin — the historical rationale is in the MCP doc.

Grafana **organization roles**, **Teams**, and the group→role mapping are documented in [rbac-multi-team.md](rbac-multi-team.md), including the Team Sync (Enterprise) caveat and how this differs from **[VMAuth / vmauth](../metrics/victoriametrics.md#vmauth--vmauth-planned)** (HTTP proxy for VictoriaMetrics APIs—not the Grafana UI).

## Datasources

All datasources are managed as `GrafanaDatasource` CRDs (GitOps, no manual configuration):

| Datasource | Type | Default | URL | Purpose |
|------------|------|---------|-----|---------|
| VictoriaMetrics | `victoriametrics-metrics-datasource` | Yes | `vmsingle-victoria-metrics:8428` | Metrics (PromQL/MetricsQL), dashboards, Explore |
| VictoriaMetrics (Prometheus) | `prometheus` | No | same VMSingle URL | prometheus-TYPE alias — what `query: prometheus` datasource variables (Envoy Gateway, Temporal, cert-manager, VM self-boards) resolve against |
| VictoriaLogs | `victoriametrics-logs-datasource` | No | `vlsingle-victoria-logs:9428` | Log queries (LogsQL), trace correlation, [plugin](https://grafana.com/grafana/plugins/victoriametrics-logs-datasource/) |
| VictoriaTraces | `jaeger` | No | `vtsingle…:10428/select/jaeger` | Trace queries + node graph. The **type** stays `jaeger` — that is the query API VictoriaTraces serves, not a leftover deployment ([RFC-0027](../../proposals/rfc/RFC-0027/README.md)) |
| ClickHouse | `grafana-clickhouse-datasource` | No | `clickhouse…:9000` | SQL over `otel.otel_logs` / `otel.otel_traces` (RFC-0019) — [ClickHouse Grafana chapter](../clickhouse/README.md#grafana), [schema-and-queries](../clickhouse/schema-and-queries.md) |
| Pyroscope | `grafana-pyroscope-datasource` | No | `pyroscope:4040` | Flamegraphs |

See [datasources.md](datasources.md) for metrics datasource details and Grafana Alerting UI notes.

**VictoriaLogs** is the 7-day ops log store, fed by **both** paths — the app fleet's OTLP tee through the collector, and Vector for everything OTel cannot instrument; use it for LogsQL queries, trace correlation, and the VM plugin workflow. The same OTLP logs are also kept 90 days in **ClickHouse** `otel_logs` for SQL. See [datasources.md](datasources.md#logs-victorialogs).

**Datasource CRD files:**

```
kubernetes/infra/configs/observability/grafana/
├── datasource-victoriametrics.yaml             # VictoriaMetrics plugin (default metrics DS)
├── datasource-victoriametrics-prometheus.yaml  # prometheus-TYPE alias (dashboards with `query: prometheus` variables)
├── datasource-victorialogs.yaml                # VictoriaLogs plugin
├── datasource-victoriatraces.yaml              # VictoriaTraces via the Jaeger query API
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

**24 `GrafanaDashboard` CRs** still vendored here, plus **18 dashboards and 6 folders
delivered as `GrafanaManifest` from an OCI artifact** (re-derive the first with
`grep -h -c '^kind: GrafanaDashboard' kubernetes/infra/configs/observability/grafana/dashboards/*.yaml`).

## Dashboards as code

Eighteen boards are no longer JSON in this repository. They are Go in
[`duynhlab/grafana-dashboards`](https://github.com/duynhlab/grafana-dashboards), rendered
with the Grafana Foundation SDK and published as one OCI artifact that Flux pins and
applies:

```text
Go builders -> dashboard.grafana.app/v2 spec -> GrafanaManifest -> OCI artifact
  -> OCIRepository grafana-dashboards-as-code-oci
  -> Kustomization ...-folders-local   (6 folders)
  -> Kustomization ...-dashboards-local (18 boards + 2 alert rule groups, dependsOn the folders)
```

Which boards: `kubernetes-cluster-overview`, `kubernetes-workloads`, `keda`, `pg-io-waits`,
`pg-maintenance`, `pg-query-performance`, `pg-exporter-instance`, `pgdog`,
`temporal-worker`, `otel-collector-health`, `microservices-monitoring-001-otel`,
`business-otel`, `red-spanmetrics`, `rfc0021-baseline`, `inventory-overview`,
`cert-manager`, `keycloak-identity`, `eg-edge`.

Two things follow from that and are easy to get wrong:

1. **Edit those boards in the Go repo, not here.** There is no JSON to edit. A change
   lands by merging there, letting CI publish, and bumping the pin in
   `kubernetes/clusters/local/sources/oci/grafana-dashboards-as-code-oci.yaml`.
2. **`GrafanaDashboard` cannot carry these boards.** It posts through the legacy
   `/api/dashboards/db` envelope and Grafana answers 400 on a Dashboard V2 payload in
   either shape. That is why they arrive as `GrafanaManifest`, and why the folders are a
   separate Flux wave the dashboards `dependsOn` — see
   [dashboards-v2.md](dashboards-v2.md).

The boards that remain as in-repo JSON are the ones nothing has ported: the ClickHouse
suite, the vendored Envoy Gateway set, `service-graph`, `cloudnative-pg`, `redis`, and the
grafana.com / flux2-monitoring-example boards fetched by `spec.url`.

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
├── datasource-victoriatraces.yaml     # VictoriaTraces (type: jaeger)
├── datasource-clickhouse.yaml         # grafana-clickhouse-datasource
├── datasource-pyroscope.yaml
├── grafana-service-account-mcp.yaml   # Viewer SA + token Secret for the Grafana MCP server
└── dashboards/
    ├── kustomization.yaml               # CR list + configMapGenerator entries (stable names, no hash)
    ├── grafana-dashboard-clickhouse*.yaml   # ClickHouse suite (configMapRef → clickhouse-*.json)
    ├── grafana-dashboard-envoy-gateway.yaml # 4 CRs (configMapRef → envoy-gateway/*.json, vendored v1.9.0)
    ├── grafana-dashboard-*.yaml         # remaining boards (spec.url → grafana.com or legacy repo)
    ├── clickhouse-*.json · service-graph.json
    └── envoy-gateway/*.json             # vendored envoyproxy/gateway v1.9.0 dashboards
```

## Related Documentation

- [RBAC and multi-team access](rbac-multi-team.md) -- staff-SSO group→role mapping (ADR-062), Teams, folder permissions
- [VMAuth and vmauth](../metrics/victoriametrics.md#vmauth--vmauth-planned) -- API-layer auth for VictoriaMetrics (separate from Grafana UI)
- [Datasource Strategy](datasources.md) -- VictoriaMetrics plugin metrics DS
- [Dashboard Reference](dashboard-reference.md) -- panel-by-panel reference
- [Variables](variables.md) -- dashboard variable configuration
- [Alerting Strategy](../alerting/README.md) -- 2-layer alerting approach
- [Metrics](../metrics/README.md) -- RED methodology and metric definitions

---
_Last updated: 2026-09-21 — added the `spec.oci` and `GrafanaManifest` delivery paths and the As-Code (V2 canary) folder; see [dashboards-v2.md](dashboards-v2.md). Previously 2026-09-05 — KEDA — Worker Autoscaling board added (ADR-055, Workflows / Async); the headline re-derived to 42 CRs / 12 folders — the 31 / 9 it had carried since 2026-08-18 was already stale. Previously 2026-08-27 — access rewritten to staff SSO (ADR-062: anonymous Admin is gone, Keycloak button is the human door, port-forward = Viewer only); retired Jaeger dropped from the intro. Previous sync 2026-08-18 (dashboard inventory)._
