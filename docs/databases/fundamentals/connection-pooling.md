# PostgreSQL Connection Pooling

Connection poolers protect PostgreSQL's process-per-connection model by sharing
a bounded set of server connections among more clients.

| Scope | Pooling semantics and selection criteria |
|---|---|
| **Not owned here** | Current endpoints, products, rotation commands |

## Why pool

Idle application connections consume backend resources, and connection setup
performs network, TLS, and authentication work. A pooler reuses connections,
limits concurrency, and queues spikes. It does not increase database capacity;
limits still come from database resources, transaction duration, and reserved
operational access.

## Pooling modes

| Mode | Server connection lifetime | Compatibility | Multiplexing |
|---|---|---|---|
| Session | Entire client session | Highest | Lowest |
| Transaction | One transaction | Session state needs care | High |
| Statement | One statement | Not general transaction-safe | Highest |

Transaction pooling changes assumptions around prepared statements, temporary
tables, advisory locks, `LISTEN/NOTIFY`, and session-level `SET`. Test the exact
driver and pooler combination.

## Routing and failure behavior

A router may classify reads and writes or balance replicas. Read routing is not
the same as consistency: a lagging replica may not see a recent commit. During
failover, stale upstream connections must be discarded and clients need bounded
retries. Monitor waiting clients, server utilization, authentication failures,
upstream health, and transaction latency.

## Applied in this homelab

See [poolers](../poolers.md) and
[pooler operations](../runbooks/pooler-operations.md). Older project-specific
notes are [archived](../reference/archive/connection-pooling-homelab-notes.md).

## References

- [PgBouncer features](https://www.pgbouncer.org/features.html)
- [PgDog documentation](https://docs.pgdog.dev/)

_Last updated: 2026-08-31._
