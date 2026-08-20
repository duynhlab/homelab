# Operational Runbooks

Runbooks for investigating, troubleshooting, and resolving incidents in the observability stack.
One folder per alert domain, one file per alert name; every alert that has a
runbook links it via its `runbook_url` annotation.

## Runbook Index

| Runbook | Purpose | When to Use |
|---------|---------|-------------|
| [Microservices runbooks](microservices/README.md) | Per-alert investigation (50 files) + cross-signal workflows, threshold tuning | On-call, when an application alert fires |
| [Envoy Gateway runbooks](envoy-gateway/README.md) | Per-alert investigation for the edge (9 files covering 11 `Edge*` / `EnvoyGateway*` alerts) | On-call, when an edge alert fires |
| [PostgreSQL runbooks](postgresql/README.md) | Per-alert CNPG runbooks (chart + deep-signal), 33 files | On-call, when a PostgreSQL/CNPG alert fires |
| [Kubernetes runbooks](kubernetes/README.md) | Per-alert investigation for pods, workloads, storage, nodes, API server, network (21 files) | On-call, when a Kubernetes infra alert fires |
| [Valkey runbooks](valkey/README.md) | Per-alert investigation for the cache (7 files) | On-call, when a Valkey alert fires |
| [Keycloak runbooks](keycloak/) | Per-alert investigation for the identity provider (5 files, no folder README yet) | On-call, when a Keycloak alert fires |
| [Logging troubleshooting](../logging/README.md#troubleshooting) | Missing/blank Kubernetes logs (Vector → VictoriaLogs → Grafana) | On-call, when logs are missing in Grafana |

Not yet covered by per-alert runbooks (a recorded gap): Flux/GitOps,
cert-manager, and observability-stack self-monitoring alerts — they
carry no `runbook_url`; the [alert catalog](../alerting/alert-catalog.md)
documents their severity and impact.

## Runbook placement

Runbooks live **next to their domain hub** (`databases/runbooks/`, `secrets/runbooks/`,
`observability/runbooks/`). There is no central `docs/runbooks/troubleshooting/` folder.

## Runbook Structure

Every per-alert runbook follows [`_TEMPLATE.md`](_TEMPLATE.md) — the one
canonical template for all domain folders:

1. **Quick facts** — severity, category, source manifest, metrics, status, dashboard
2. **Meaning** — what fires and when
3. **Impact** — operational consequence
4. **Diagnosis** — PromQL, Grafana, kubectl/logs, VictoriaLogs/traces
5. **Mitigation** — resolution actions, cheapest first
6. **Escalation** — page-vs-ticket call and what not to do

Domain-specific rows and diagnosis dialects live in each folder README's
"Domain specifics" section, never in a forked template.

## Related Documentation

- [Alerting Strategy](../alerting/README.md) -- 2-layer alerting architecture
- [SLO System](../slo/README.md) -- SLO definitions and burn-rate alerts
- [Grafana Datasources](../grafana/datasources.md) -- how to view rules in Grafana UI
- [PostgreSQL metrics hub](../metrics/postgresql/README.md) — custom queries, workflows, learning path
- [Database HA Scaling](../../databases/runbooks/zalando-ha-scaling.md) — historical Zalando HA reference
- [Prepared Databases](../../databases/runbooks/prepared-databases.md) -- preparedDatabases issue runbook

---
_Last updated: 2026-08-19 — infrastructure-alerts.md split into kubernetes/ + valkey/; one canonical template_
