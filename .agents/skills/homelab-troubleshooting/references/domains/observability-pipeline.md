# Telemetry pipeline

When signals are **missing** (no metrics, blank logs, no traces/profiles) the
incident is in the pipeline, not the app. A "service down" with a dead exporter
is a telemetry incident.

## Authoritative docs

- Stack map and correlation: [observability/README.md](../../../../../docs/observability/README.md).
- Collector deep dive: [opentelemetry/collector.md](../../../../../docs/observability/opentelemetry/collector.md).
- Log pipeline + troubleshooting: [logging/vector.md § Troubleshooting](../../../../../docs/observability/logging/vector.md#troubleshooting),
  [logging/victorialogs.md](../../../../../docs/observability/logging/victorialogs.md).
- Collector/watchdog alerts: `docs/observability/runbooks/observability/`
  (per-alert files; **no folder README** — a recorded gap).
- VictoriaMetrics self-health: `docs/observability/runbooks/victoriametrics/`
  (per-alert files; **no folder README** — a recorded gap).
- App instrumentation policy (service repos, via `pkg/obsx`):
  [api/observability.md](../../../../../docs/api/observability.md).

## Manifests

- Collector: `kubernetes/infra/controllers/tracing/otel-collector/`
- Vector: `kubernetes/infra/controllers/logging/vector/vector.yaml`
- VM stack rules: `kubernetes/infra/configs/observability/metrics/prometheusrules/{observability,victoriametrics}/`

## Diagnose

- Confirm the exporter path: target → scrape/OTLP → store. Empty vector is not a
  healthy zero ([evidence-correlation](../evidence-correlation.md)).
- RFC-0014 relabeling moved `job`/label shapes — a "missing" series is often a
  stale selector.
- App logs go OTLP (otelzap tee); Vector ships only non-instrumented pods (DBs,
  PG plans, frontend) and the edge runtime lines. Blank Grafana logs → start in
  the Vector troubleshooting section.

```bash
make e2e-observability   # datasources, dashboards, panel path, scrape targets (compose C17–C20)
```

## Boundary

Changing instrumentation is a service-repo change (`pkg/obsx`), not an incident
mitigation. Fix the pipeline here; route code changes to the owning repo.

## Known traps

Verified against the repo on 2026-10-29. Each line points at the doc that
owns the detail.

- Collector self-metrics have no `_total` suffix, and a failure series appears only after the first failure — [collector § Operations](../../../../../docs/observability/opentelemetry/collector.md#operations).
- Keep Grafana `preinstall_auto_update: "false"`: on a read-only root FS the plugin self-update unregisters the bundled datasources — [Grafana § Plugins](../../../../../docs/observability/grafana/README.md#plugins).
- On Kind the Grafana operator creates but cannot update dashboards, datasources or rule groups (#1273) — [Grafana § Dashboards as code](../../../../../docs/observability/grafana/README.md#dashboards-as-code).
