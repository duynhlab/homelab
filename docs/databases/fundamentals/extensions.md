# PostgreSQL Extensions

An extension packages related SQL objects and sometimes native code into a
versioned unit PostgreSQL can install and upgrade within a database.

| Scope | Extension lifecycle, trust, and risk |
|---|---|
| **Not owned here** | Current installed extensions or operand image |

## Availability and activation

Extension files must exist on every server that may run the database.
`CREATE EXTENSION` then registers and creates objects inside one database.
Installing a package does not activate it; running `CREATE EXTENSION` cannot
make missing binaries appear. Libraries in `shared_preload_libraries` are a
cluster-wide startup concern while extension objects remain database-scoped.

## Security and compatibility

Treat native extensions as server code. Review provenance, PostgreSQL version
support, privileges, update scripts, restore behavior, and trust settings. A
restore needs compatible control files, SQL scripts, and libraries on the
destination. Deliver artifacts immutably and rehearse updates and restores.

## Lifecycle

1. Establish the workload need.
2. Confirm PostgreSQL and platform compatibility.
3. Review privilege and native-code risk.
4. Make artifacts available on every eligible server.
5. Activate the extension in the intended database.
6. Verify version, preload state, metrics, backup, and restore.
7. Test update and rollback before rollout.

Dropping an extension can remove every member object. Treat it as a destructive
schema migration.

## Applied in this homelab

See [platform extensions](../extensions.md). Historical implementation notes
are [archived](../reference/archive/extensions-homelab-notes.md).

## References

- [PostgreSQL extension packaging](https://www.postgresql.org/docs/current/extend-extensions.html)
- [`CREATE EXTENSION`](https://www.postgresql.org/docs/current/sql-createextension.html)
- [`ALTER EXTENSION`](https://www.postgresql.org/docs/current/sql-alterextension.html)

_Last updated: 2026-08-31._
