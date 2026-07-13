# PostgreSQL Prometheus rules (by cluster)

All Postgres runs on CloudNativePG; the CNPG chart rule set is split per cluster.

| Directory | Cluster | Notes |
|-----------|---------|--------|
| [`cnpg/`](cnpg/) | product-db (ns `product`, 3-node HA) | Chart-derived rules (`cnpg/cluster` v0.6.0), one file per upstream `cluster-*.yaml` fragment; plus small extras (`cluster-fenced`, `cluster-wal-size-high`). |
| [`cnpg-auth-db/`](cnpg-auth-db/) | auth-db (ns `auth`, 3-node HA) | Full rule set mirrored from `cnpg/`; `operator-health` is a global singleton and not duplicated. |
| [`cnpg-shared-db/`](cnpg-shared-db/) | shared-db (ns `user`, single-node) | Only rules that fire on one instance (offline, high-connection, WAL size, low disk); HA/replication rules omitted. |

`backup-alerts.yaml` covers Barman backup freshness across clusters. The former
monolith `postgres-alerts.yaml` and the retired `zalando/` rules were removed in
favor of this layout.

**Dedupe matrix:** When chart alerts overlap older names (e.g. `CNPGClusterOffline` vs `CnpgDown`), the chart rules are authoritative for CNPG; see [`cnpg/README.md`](cnpg/README.md).

## Ownership and review boundaries

- Each cluster's alerts are owned in its own directory (`cnpg/`, `cnpg-auth-db/`, `cnpg-shared-db/`) and should not be mixed across clusters.
- Dedupe decisions are made by symptom/scope; keep intended warning/critical pairs, remove only true duplicates.

