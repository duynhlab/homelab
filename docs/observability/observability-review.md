# Observability Review

> **Scope**: `docs/observability/` + the GitOps observability tooling under
> `kubernetes/infra/` (VictoriaMetrics stack, Grafana, Tempo/Jaeger, OTel Collector,
> Vector, VictoriaLogs, Pyroscope, Sloth/SLO, alerting).
> **Method**: five-axis review (correctness, readability, architecture, security,
> performance) with an adversarial fresh-context sweep; every non-trivial finding was
> **reconciled against the live manifests** before it was allowed to stand.
> **Calibration**: this is a **Kind homelab**, not a production cluster. Production-HA
> expectations (multi-replica Alertmanager, multi-month retention, paging integrations)
> are intentionally out of scope and are *not* counted as defects.

## Verdict

The stack is **solid and coherent for a homelab**. The four pillars
(metrics / traces / logs / profiles) are complete and navigable; the SLO layer works; the
alerting pipeline has a Watchdog dead-man's-switch, broad target-down coverage, severity
inhibition, and a Karma dashboard. The findings below are a short list of **correctness /
consistency defects** plus a set of **documented recommendations** for if/when this graduates
toward production.

## Reconciled false-positives (recorded so they are not re-litigated)

| Claim raised | Verdict | Evidence |
|---|---|---|
| "Sloth is deployed but non-functional — no `PrometheusServiceLevel` CRs, no burn-rate alerts." | **NOISE** | All 4 domain ResourceSets set `slo.enabled: true` (`kubernetes/apps/domains/{identity,catalog,checkout,comms}-rs.yaml`). The `mop` chart renders a `PrometheusServiceLevel` **per service at deploy time** (`docs/observability/slo/README.md`); Sloth turns those into burn-rate `PrometheusRule`s that VMAlert evaluates. The CRs are render-time, not static YAML — their absence from the repo is by design. |
| "Loki is a single-replica `emptyDir` SPOF." | **NOISE → surfaces a real defect** | Loki is **not deployed at all** — `kubernetes/infra/controllers/logging/kustomization.yaml` includes only `vector/`. The leftover Loki files are dead code (see below). |

## Findings — confirmed actionable

| # | Severity | Finding | Location |
|---|----------|---------|----------|
| 1 | 🟠 Med | **Dead Loki manifests** contradict the "VictoriaLogs-only" design. The deployment/service/configmap and a Grafana datasource + dashboard exist on disk but are wired into **no** kustomization. | `controllers/logging/loki/*`, `configs/monitoring/grafana/datasource-loki.yaml`, `configs/monitoring/grafana/dashboards/grafana-dashboard-loki.yaml` |
| 2 | 🟠 Med | **No PVC-near-full alert.** Metrics + logs PVCs are small (20Gi each) with `removePvcAfterDelete: true`; `kubelet_volume_stats_*` is already scraped, so the alert is free to add. A full PVC silently halts ingestion. | `configs/monitoring/prometheusrules/` |
| 3 | 🟡 Low | **Tempo has no target-down alert** even though it *is* scraped (`servicemonitors/tempo.yaml`); the `VMServiceDown` rule's regex matches only VM components. | `prometheusrules/victoriametrics/health-alerts.yaml` |
| 4 | 🟡 Low | **Three alerts fire on a single eval (no `for:`)** → flaky on transient restarts/reloads: `VMTooManyRestarts`, `VMAlertConfigurationReloadFailure`, `VMAgentConfigurationReloadFailure`. | `prometheusrules/victoriametrics/{health,vmalert,vmagent}-alerts.yaml` |
| 5 | 🟡 Low | **Doc drift.** Dashboard is **40 panels / 6 rows**, not 34/5 (`metrics/README.md` was already correct; the others lagged). One runbook diagram shows Sloth **v0.15.0** (deployed: v0.16.0). Alerting docs said Slack/routing was "planned / single default receiver" — it is in fact **wired** (see #6). | `grafana/*`, `runbooks/observability-deep-dive.md`, `alerting/*` |

*(Findings 1–5 are addressed in this change set; the doc-drift fixes ship with this review,
the manifest fixes 1–4 in a companion PR.)*

## Findings — documented recommendations (intentionally not changed now)

- 🔴 **No scrape coverage for OTel Collector, Pyroscope, or Vector** (and VictoriaLogs is not
  in the `VMServiceDown` regex). A "target-down" alert for these would never fire because they
  have no `up` series. The real fix is to add a `VMServiceScrape`/`PodMonitor` per component
  and confirm each exposes Prometheus metrics on a known port — a larger change than this pass.
  Until then, an outage of the trace/log/profile pipeline is **invisible to alerting**.
- 🔴 **Tempo and Pyroscope use `emptyDir`** (`controllers/tracing/tempo/deployment.yaml`,
  `controllers/profiling/pyroscope/deployment.yaml`) → in-flight traces/profiles are lost on
  pod restart. Given short retention (Tempo ~1h, Pyroscope 24h) on a homelab this is arguably
  intentional; attach a small PVC if persistence across restarts is wanted.
- 🟠 **Alerting notifications do not deliver.** VMAlertmanager has `slack-default`/`slack-critical`
  receivers wired with routing + inhibition, but `slack_api_url` is a committed placeholder
  (`<SLACK_WEBHOOK_URL>`) with no secret-injection mechanism. Inject it via External Secrets /
  OpenBAO — and avoid inlining the real secret into `configRawYaml`.
- 🟠 **Grafana is anonymous-admin** (`auth.anonymous.enabled=true`, `org_role=Admin`,
  login disabled). Fine for a local homelab; for any shared/exposed deployment, default the
  anonymous role to `Viewer` and enable OIDC for named admins.
- 🟡 **Kyverno resource hygiene.** The grafana-operator HelmRelease and metrics-server do not
  set explicit `resources.requests/limits` in the GitOps values; confirm they are actually
  admitted (chart defaults may satisfy the policy) and pin them explicitly if not.

## Five-axis summary

- **Correctness** — Scrape coverage is good for the apps/DB/gateway/control-plane tier; the
  gaps are the *observability components themselves* (#3, recommendation above). Alert rules are
  sound apart from the missing `for:` (#4).
- **Readability** — Docs are well-structured (A−). Main drift was numeric/version (#5), now fixed.
- **Architecture** — Clean: operator-managed VM stack, Sloth render-time SLOs, Vector→VictoriaLogs,
  OTel fan-out to Tempo+Jaeger. The dead Loki files (#1) are the one architectural smell.
- **Security** — Anonymous-admin Grafana and the inline Slack-webhook placeholder are the notable
  items; both are homelab-acceptable and documented above.
- **Performance / cost** — Cardinality is controlled (kube-apiserver metric-relabel allowlist,
  bounded path labels). Small PVCs (20Gi) are the main scaling limit → motivates #2.

## Related

- [Observability index](README.md) · [Alerting](alerting/README.md) · [SLO](slo/README.md)
- [API architecture review](../architecture/api-architecture-review.md) — companion review
