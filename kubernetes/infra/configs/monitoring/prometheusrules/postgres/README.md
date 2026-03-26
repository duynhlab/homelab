# PostgreSQL Prometheus rules (by operator)

| Directory | Operator | Notes |
|-----------|----------|--------|
| [`cnpg/`](cnpg/) | CloudNativePG | Chart-derived rules (`cnpg/cluster` v0.6.0), one file per upstream `cluster-*.yaml` fragment; plus small extras (`cluster-fenced`, `cluster-wal-size-high`). |
| [`zalando/`](zalando/) | Zalando | Legacy split from former `postgres-alerts.yaml` — availability, `custom_*` performance, storage, maintenance. |

The former monolith `postgres-alerts.yaml` was removed in favor of this layout.

**Dedupe matrix:** When chart alerts overlap older names (e.g. `CNPGClusterOffline` vs `CnpgDown`), the chart rules are authoritative for CNPG; see [`cnpg/README.md`](cnpg/README.md).

## Ownership and review boundaries

- CNPG-specific alerts are owned in [`cnpg/`](cnpg/) and should not be mixed into Zalando files.
- Zalando-specific alerts are owned in [`zalando/`](zalando/) and should not include CNPG branches.
- Dedupe decisions are made by symptom/scope; keep intended warning/critical pairs, remove only true duplicates.

## Guardrail check

Run `make postgres-alert-audit` after reconciliation to quickly check:
- Flux readiness for monitoring/database layers.
- Duplicate PostgreSQL alert names.
- Metric backing for enabled rules (`cnpg_*`, `custom_*`, `kube_*`, `kubelet_*`).
- VMAlert runtime rule errors.

