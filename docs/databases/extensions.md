# PostgreSQL Extension Policy

This page owns the extension delivery and activation model currently declared
for the CloudNativePG clusters.

| Item | Current state |
|---|---|
| **Operand image** | `ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie` |
| **Delivery model** | Extensions already present in the system operand image |
| **Activation** | Cluster preload list plus per-database `Database.spec.extensions` |
| **Image-volume extensions** | Not deployed |

## Cluster preload

Both operational clusters preload `pgaudit`, `pg_stat_statements`, and
`auto_explain`. `auto_explain` is a preload-only module and is not declared as a
SQL extension.

## Per-database declarations

| Database set | Declared extensions |
|---|---|
| `product` | `pgaudit`, `pg_stat_statements`, `pgcrypto`, `uuid-ossp` |
| `cart`, `order`, `payment`, `checkout`, `inventory` | `pgaudit`, `pg_stat_statements` |
| `user`, `notification`, `shipping`, `review`, `keycloak` | `pgaudit`, `pg_stat_statements` |
| `temporal`, `temporal_visibility` | `pg_stat_statements` |

Per-service `Database` resources use `databaseReclaimPolicy: retain`. A new
extension is not approved merely because the operand image contains it. The
change must establish workload need, privileges, version compatibility,
backup/restore behavior, and observability before its declaration is added.

## Change workflow

1. Confirm the extension is available and compatible with PostgreSQL 18.1.
2. Review native-code and superuser requirements.
3. Decide whether a restart-time preload is required.
4. Add the database-scoped declaration to the owning service manifest.
5. Validate reconciliation and `pg_extension` state.
6. Prove backup/restore and rollback before relying on the extension.

Use [extension fundamentals](./fundamentals/extensions.md) for the underlying
lifecycle and [declarative role management](./declarative-role-management.md)
for the service triplet contract.

## Manifest evidence

- `kubernetes/infra/configs/databases/clusters/{platform-db,product-db}/instance.yaml`
- `kubernetes/infra/configs/databases/clusters/{platform-db,product-db}/services/*.yaml`

## References

- [CloudNativePG declarative database management](https://cloudnative-pg.io/documentation/current/declarative_database_management/)
- [PostgreSQL extension packaging](https://www.postgresql.org/docs/current/extend-extensions.html)

_Last updated: 2026-08-31._
