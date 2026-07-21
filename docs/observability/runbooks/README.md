# Operational Runbooks

Runbooks for investigating, troubleshooting, and resolving incidents in the observability stack.

## Runbook Index

| Runbook | Purpose | When to Use |
|---------|---------|-------------|
| [Observability Deep Dive](observability-deep-dive.md) | RED/USE/Golden Signals theory, 4-pillar stack architecture, middleware chain, correlation workflow, interview preparation | Learning, onboarding, interview prep |
| [Infrastructure Alerts](infrastructure-alerts.md) | Per-alert investigation guide for infrastructure/platform alerts (nodes, control plane, Flux, cert-manager, VictoriaMetrics) | On-call, when an infrastructure alert fires |
| [Microservices Alerts](microservices-alerts.md) | Workflows, tuning, and design context for application alerts | Learning, cross-signal triage |
| [Microservices runbooks](microservices/README.md) | Per-alert investigation (19 files) | On-call, when an application alert fires |
| [PostgreSQL Alerts](postgresql/README.md) | Per-alert CNPG runbooks (chart + deep-signal), one file per alert name | On-call, when a PostgreSQL/CNPG alert fires |
| [VictoriaLogs Kubernetes Logs Debug](victorialogs-kubernetes-logs-debug.md) | Blank Grafana logs panel / empty Explore against VictoriaLogs | On-call, when Kubernetes logs are missing in Grafana |

## Runbook placement

Runbooks live **next to their domain hub** (`databases/runbooks/`, `secrets/runbooks/`,
`observability/runbooks/`). There is no central `docs/runbooks/troubleshooting/` folder.

## Runbook Structure

Each alert runbook follows a consistent format (CNPG upstream style for PostgreSQL):

1. **Meaning** — what fires and when
2. **Impact** — operational consequence
3. **Diagnosis** — PromQL, Grafana, kubectl/psql
4. **Mitigation** — resolution actions
5. **Escalation** — optional homelab extension

## Related Documentation

- [Alerting Strategy](../alerting/README.md) -- 2-layer alerting architecture
- [SLO System](../slo/README.md) -- SLO definitions and burn-rate alerts
- [Grafana Datasources](../grafana/datasources.md) -- how to view rules in Grafana UI
- [PostgreSQL metrics hub](../metrics/postgresql/README.md) — custom queries, workflows, learning path
- [Database HA Scaling](../../databases/runbooks/zalando-ha-scaling.md) — historical Zalando HA reference
- [Prepared Databases](../../databases/runbooks/prepared-databases.md) -- preparedDatabases issue runbook

---
_Last updated: 2026-07-21_
