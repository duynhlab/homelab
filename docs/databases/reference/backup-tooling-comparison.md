# PostgreSQL Physical Backup Tooling

WAL-G, pgBackRest, and Barman all support physical PostgreSQL recovery, but they
place automation, repository management, and operator integration in different
layers.

| Item | Scope |
|---|---|
| **Purpose** | Learning and design comparison |
| **Current platform choice** | Documented separately in `backup-policy.md` |
| **Not provided here** | Product selection without workload and restore evidence |

## Comparison

| Dimension | WAL-G | pgBackRest | Barman / Barman Cloud |
|---|---|---|---|
| Primary shape | Lightweight backup and WAL archive client | Repository-oriented backup suite | Backup server or cloud-object-storage tooling |
| Repository features | Object-store focused | Full, differential, incremental and repository policies | Catalog, retention, recovery and cloud interfaces |
| Common integration | Sidecar, script, image or operator wrapper | Dedicated repository host/pod or operator integration | External server, cloud commands or database-operator plugin |
| Main strength | Simple cloud-native artifact movement | Rich backup types and repository controls | Broad PostgreSQL operations model and mature operator integrations |
| Main cost | More lifecycle policy must be assembled around it | More components and configuration | Integration shape varies between server and cloud modes |

The table is a starting point, not a winner. The decisive evidence is whether a
tool can repeatedly restore the required data volume within the target RTO while
preserving the required WAL chain, encryption, retention, and failure-domain
independence.

## Evaluation questions

1. Which PostgreSQL versions, backup formats, compression and encryption modes
   are supported?
2. Who owns WAL archiving, retention, deletion, integrity checks and repository
   credentials?
3. Can a restore select time, transaction, recovery point or latest state?
4. How are partial uploads, missing WAL, repository corruption and expired
   credentials surfaced?
5. Does the chosen database operator provide a supported integration, or must
   the platform own sidecars and lifecycle hooks?
6. Can the same artifacts restore outside the original cluster and control
   plane?
7. What restore throughput and WAL replay rate have been measured with realistic
   data?

## Selection rule

Prefer the tool with the smallest operational ownership surface that still
meets recovery objectives. Feature count is secondary to tested restoration,
clear failure signals, and an upgrade path compatible with the database control
plane.

## References

- [WAL-G documentation](https://wal-g.readthedocs.io/)
- [pgBackRest user guide](https://pgbackrest.org/user-guide.html)
- [Barman documentation](https://docs.pgbarman.org/)
- [PostgreSQL continuous archiving](https://www.postgresql.org/docs/18/continuous-archiving.html)

_Last updated: 2026-08-31._
