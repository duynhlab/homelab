# Grafana

Grafana is the unified visualization layer for all 4 observability pillars. It connects to VMSingle (metrics), Tempo (traces), Loki (logs), Jaeger (traces), and Pyroscope (profiles) through configured datasources.

## Deployment

Grafana is deployed via the **Grafana Operator** using a `Grafana` CR:

- **CR**: `kubernetes/infra/configs/monitoring/grafana/grafana.yaml`
- **Image**: `grafana/grafana:12.4.1`
- **Namespace**: `monitoring`
- **Access**: anonymous login with Admin role (dev mode)

```bash
kubectl port-forward svc/grafana-service -n monitoring 3000:3000
# Open http://localhost:3000
```

## Datasources

All datasources are managed as `GrafanaDatasource` CRDs (GitOps, no manual configuration):

| Datasource | Type | Default | URL | Purpose |
|------------|------|---------|-----|---------|
| Prometheus | `prometheus` | Yes | `vmsingle-victoria-metrics:8428` | Metrics, alerting, read-only rules |
| VictoriaMetrics | `victoriametrics-metrics-datasource` | No | `vmsingle-victoria-metrics:8428` | MetricsQL, VMUI integration |
| Loki | `loki` | No | `loki:3100` | Log queries (LogQL) |
| Tempo | `tempo` | No | `tempo:3200` | Trace queries |
| Jaeger | `jaeger` | No | `jaeger-query:16686` | Trace search (alternative UI) |
| Pyroscope | `grafana-pyroscope-datasource` | No | `pyroscope:4040` | Flamegraphs |

Both **Prometheus** and **VictoriaMetrics** datasources point to the same VMSingle backend. See [datasources.md](datasources.md) for the rationale and case study.

**Datasource CRD files:**

```
kubernetes/infra/configs/monitoring/grafana/
├── datasource-prometheus.yaml
├── datasource-victoriametrics.yaml    # VictoriaMetrics plugin
├── datasource-loki.yaml
├── datasource-tempo.yaml
├── datasource-jaeger.yaml
└── datasource-pyroscope.yaml
```

## Plugins

Plugins are installed via the `GF_INSTALL_PLUGINS` environment variable in the Grafana CR:

| Plugin | Version | Purpose |
|--------|---------|---------|
| `victoriametrics-metrics-datasource` | 0.23.1 | Native VictoriaMetrics datasource with MetricsQL support |

The plugin must also be listed in `allow_loading_unsigned_plugins` since it is not signed by Grafana:

```yaml
spec:
  config:
    plugins:
      allow_loading_unsigned_plugins: victoriametrics-metrics-datasource
```

## Dashboards

Dashboards are managed as `GrafanaDashboard` CRDs or JSON ConfigMaps:

| Dashboard | Panels | Location |
|-----------|--------|----------|
| Microservices Observability | 34 panels, 5 rows | `grafana/dashboards/microservices-dashboard.json` |

Dashboard documentation:
- [Dashboard Reference](dashboard-reference.md) -- all 34 panels, queries, and what they measure
- [Variables](variables.md) -- `$app`, `$namespace`, `$rate` and regex patterns

## Alerting UI

Grafana's **Alerting > Alert rules** page shows two types of rules:

1. **Grafana-managed rules** -- created in Grafana UI, stored in Grafana DB
2. **Data source-managed rules (read-only)** -- fetched from external systems via `/api/v1/rules`

For our setup, all alert rules are **data source-managed** (read-only) because they are defined as `PrometheusRule` CRDs and evaluated by VMAlert. Grafana displays them by querying VMSingle, which proxies the request to VMAlert via `vmalert.proxyURL`.

See [datasources.md](datasources.md) for the full technical explanation.

## Manifest Locations

```
kubernetes/infra/configs/monitoring/grafana/
├── grafana.yaml                       # Grafana CR (operator-managed)
├── datasource-prometheus.yaml         # Prometheus-type datasource (default)
├── datasource-victoriametrics.yaml    # VictoriaMetrics plugin datasource
├── datasource-loki.yaml
├── datasource-tempo.yaml
├── datasource-jaeger.yaml
├── datasource-pyroscope.yaml
└── dashboards/
    └── microservices-dashboard.json
```

## Related Documentation

- [Datasource Strategy](datasources.md) -- dual datasource case study
- [Dashboard Reference](dashboard-reference.md) -- panel-by-panel reference
- [Variables](variables.md) -- dashboard variable configuration
- [Alerting Strategy](../alerting/README.md) -- 2-layer alerting approach
- [Metrics](../metrics/README.md) -- RED methodology and metric definitions
