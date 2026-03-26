# Zalando Postgres Operator — Prometheus rules

Rules for clusters managed by the [Zalando Postgres Operator](https://github.com/zalando/postgres-operator): **`auth-db`** (postgres_exporter + `custom_*` queries) and **`supporting-shared-db`** (Pigsty `pg_exporter` — often `pg_*` / `pg_cluster_*`).

Split from the former `postgres-alerts.yaml` monolith so CNPG-specific alerts live under [`../cnpg/`](../cnpg/).

## Layout

| File | Scope |
|------|--------|
| `availability.yaml` | `pg_up`, `pg_replication_lag` (Spilo / streaming) |
| `performance.yaml` | Connection saturation & lock contention for **custom_** metrics (auth-db); extend for Pigsty if needed |
| `storage.yaml` | Database size (`pg_*` / `pg_database_size_bytes`) without CNPG-only series |
| `maintenance.yaml` | Dead tuples, checkpoints — Zalando / pg_exporter paths |

## Note on mixed exporters

`supporting-shared-db` metric names may differ from `auth-db` `custom_*`. Add rules or recording rules when you standardize queries per cluster.
