# ADR-089: Define the PostgreSQL Access Contract Between Applications and the Platform

> **Decision summary:** We will give every PostgreSQL consumer one contract:
> migrations connect directly to the primary, application and other SQL
> consumers go through PgDog or PgBouncer to the primary by default, both
> pooled hops verify the server certificate and hostname, every connection
> carries a stable `application_name`, and each role has one password writer
> on a declared cadence. Operator, replication, per-instance monitoring,
> backup and break-glass keep their native paths. We accept TLS issuance and
> reload work, a per-version pooler compatibility matrix and turning off
> PgDog's automatic read split, in exchange for connections that are
> encrypted, attributable and predictable in their consistency.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-10-15 |
| **Owners** | `platform` |
| **Deciders** | `owner (duynhlab)` |
| **Scope** | Every connection to the CNPG clusters `platform-db` and `product-db` |
| **Affected components** | domain ResourceSets and workers (`PGAPPNAME`, endpoints, sslmode), CNPG Pooler `platform-db-pooler-rw`, PgDog `pgdog-product`, certificates (RFC-0020), OpenBAO/ESO credential delivery, local-stack |
| **Related RFC** | [RFC-0029](../../rfc/RFC-0029/) |
| **Related research** | [research.md](../../rfc/RFC-0029/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | [issue #1269](https://github.com/duynhlab/homelab/issues/1269) |
| **Adoption** | Not started |

## Context

[ADR-088](../ADR-088-platform-owns-database-authorization/) settled who owns
roles and grants. It did not settle how consumers reach the database. On
`main` (repository review, 2026-10-15):

- Nine of ten services connect with `sslmode=disable`; payment uses `require`
  directly against the primary, without verification.
- No workload sets `application_name`. In query telemetry, platform-db events
  have an empty `app` and product-db events read `PgDog`.
- PgDog sends every `SELECT` outside a transaction to the replicas, so a read
  that follows a committed write can be stale.
- Migrations already connect directly to the primary.

The RFC holds the details: the current baseline, connection matrix, pooler
evidence and naming table.

## Decision drivers

1. A credential or packet in transit is not readable or spoofable inside the cluster.
2. Every query in telemetry names the workload that sent it.
3. A service gets connection details and never discovers primaries or manages pooler internals.
4. Reads are fresh unless a flow opts into staleness.
5. A password change reaches every consumer through one writer, without a competing reconciler.

## Decision

```mermaid
flowchart LR
    subgraph cluster["Kind cluster · homelab — planned target contract"]
        app["API · workers · data · CDC · platform SQL"]:::service
        mig["migrations"]:::worker
        native["operator · replication · per-instance monitoring<br/>backup · break-glass"]:::platform
        pool["PgDog / PgBouncer"]:::platform
        prim[("primary")]:::data
        rep[("replica")]:::data
    end
    app -->|"verify-full · application_name"| pool
    pool -->|"verify-full · default"| prim
    pool -. "explicit stale-read profile only" .-> rep
    mig -->|"direct · verify-full · owner-at-login"| prim
    native -. "native path, not pooled" .-> prim

    classDef service fill:#cffafe,color:#164e63,stroke:#0891b2;
    classDef worker fill:#fef3c7,color:#78350f,stroke:#d97706;
    classDef platform fill:#ede9fe,color:#4c1d95,stroke:#7c3aed;
    classDef data fill:#dcfce7,color:#14532d,stroke:#16a34a;
```

All of it is the target. Today's routes are drawn in the
[RFC](../../rfc/RFC-0029/#architecture--diagrams).

| Topic | Decision |
|---|---|
| Migration | Direct primary (`-rw`), never pooled; the migrator acts as the owner at login (ADR-088); one backend for each advisory-lock lifetime |
| Other consumers | API, workers, data robots, CDC and platform SQL use a compatible pooler profile; payment, Keycloak, Temporal and OpenBAO move from their direct paths through gated cutovers |
| Native paths | CNPG operator, streaming replication, the per-instance exporter, `pg_stat_ch`, Barman and break-glass are not pooled |
| Poolers | Keep PgDog and CNPG PgBouncer; compatibility is verified per deployed version |
| TLS | `verify-full` on client → pooler and pooler → PostgreSQL, and on the direct migration hop; no plaintext or no-verify fallback. CA rotation: trust old and new, reload, switch the certificate, verify, remove the old trust |
| Attribution | `application_name` is required: the workload name (`order`, `order-worker`), `<name>-migrate` for migrations, no environment suffix; delivered as `PGAPPNAME` |
| Consistency | Primary by default; a replica only through an explicit stale-read profile with a declared lag tolerance; PgDog's automatic read split is turned off; no blind replay of an ambiguous write |
| Credentials | Fixed usernames; one writer per password; runtime and data automatic 30 days, migrator and authz manual 30 days, monitoring automatic 90 days, CDC manual 90 days with a monthly review; break-glass rotates after use |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|---|---|---|---|
| Migrations through the pooler | One endpoint per service | A transaction pooler moves session advisory locks between backends; DDL would depend on pooler availability | Rejected |
| Monitoring through the pooler | Uniform routing | A pooler reaches one primary and hides the replicas; the exporter already runs inside each instance | Rejected |
| `require` without verification | No certificate work | Encrypts but does not authenticate the server | Rejected |
| Keep PgDog's automatic read split | Offloads reads from the primary | Read-after-write is stale outside a transaction, with no opt-in per flow | Rejected; becomes an explicit profile |
| Replace one of the two poolers | One compatibility matrix | No measured reason to migrate either | Rejected |

## Consequences

### Positive

- A leaked packet or a spoofed endpoint no longer exposes a credential.
- Query telemetry can filter by workload on both clusters.
- Fresh reads are the default and staleness is visible in configuration.

### Negative and accepted trade-offs

- Certificates for each pooler Service, and reload paths for clients and poolers.
- One extra `SET` whenever PgDog hands a backend to a client with a different name.
- The primary carries the read load PgDog moves to replicas today.
- PgDog's static user list must go (`passthrough_auth`, ADR-025) before automatic runtime rotation on product-db.

## Implementation obligations

- Set `PGAPPNAME` per the naming table in the RFC, application workloads first.
- Pooler profiles: a CNPG Pooler `clientTLSSecret` and `server_tls_sslmode: verify-full`; PgDog `tls_verify = verify_full` with its server CA, and no automatic read split.
- Confirm each pooler setting on the deployed version, and again after a pooler bump.
- Set the CA overlap, renewal thresholds and error budget before the first certificate switch.

## Validation and compliance

| Requirement | Verification |
|---|---|
| Attribution | `SHOW application_name` per workload; interleaved clients through each pooler stay correctly labelled in `pg_stat_ch` |
| TLS | Correct CA and hostname pass; a wrong CA, a wrong hostname and plaintext each fail, on every hop |
| Consistency | Read-after-write through the default pool returns the write |
| Rotation | Fresh client and backend authentication after a change, consumer reload, recovery from a mismatch |

## Revisit triggers

- A pooler version drops a capability this contract relies on.
- CDC cannot pass its replication gate through a pooler.
- A measured read load needs replicas by default.

## References

- [RFC-0029](../../rfc/RFC-0029/) — baseline, connection matrix, pooler evidence, naming table, rollout
- [ADR-088](../ADR-088-platform-owns-database-authorization/), [ADR-084](../ADR-084-split-service-database-roles/), [ADR-014](../ADR-014-pooler-credentials-valuesfrom/), [ADR-015](../ADR-015-pg-hba-connection-isolation/), [ADR-025](../ADR-025-pgdog-passthrough-dynamic-db-creds/), [ADR-026](../ADR-026-platform-db-pgbouncer-pilot/)
- [RFC-0020](../../rfc/RFC-0020/) — internal TLS ownership

## History

- 2026-10-15 — Accepted with the RFC-0029 access-contract refactor; adoption not started.
