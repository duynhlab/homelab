# ADR-026: Pilot CNPG-native PgBouncer pooler on platform-db

Replace the PgDog pooler on **platform-db only** with CloudNativePG's native
**`Pooler` (PgBouncer)**, keeping product-db on PgDog. A one-cluster pilot to run the
tool most real-world Postgres shops use and to compare it against PgDog in-place.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-07-20 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | `platform-db` pooling only — `product-db` stays on PgDog |
| **Affected components** | `platform-db` Pooler, the five platform service DSNs, platform NetworkPolicy, rotation runbook |
| **Related RFC** | [RFC-0012](../../rfc/RFC-0012/), [RFC-0018](../../rfc/RFC-0018/) (whose `pgdog-platform` this replaces) |
| **Related ADR** | [ADR-014](../ADR-014-pooler-credentials-valuesfrom/), [ADR-015](../ADR-015-pg-hba-connection-isolation/), [ADR-025](../ADR-025-pgdog-passthrough-dynamic-db-creds/) |
| **Adoption** | Complete |

**Adoption evidence (2026-08-07).** `Pooler/platform-db-pooler-rw` is the only
pooler in namespace `platform`; no `pgdog-platform` HelmRelease exists anywhere in
the tree. All five platform services carry
`db_host: platform-db-pooler-rw.platform.svc.cluster.local` at runtime with
`db_migration_host: platform-db-rw...` for their initContainers, and the platform
NetworkPolicy allows `:5432` for both. The docs that still described PgDog on this
cluster were swept in the same change as this flip — the drift is what surfaced
the un-flipped status.

> **Every decision is a tradeoff.** PgBouncer via CNPG is simpler and battle-tested with
> operator-managed auth, but we give up PgDog's read/write split, replica load-balancing,
> and sharding on this cluster.

## Context

Both clusters pool through **PgDog** (third-party, chart `v0.39`): a static, positional
`users[]` list with passwords injected by Flux `valuesFrom` from the per-service ESO
secrets (ADR-014), doing read/write split across `-rw`/`-r`. PgBouncer is the pooler most
production Postgres teams run, and CloudNativePG ships a **native `Pooler`** for it — worth
learning hands-on. Rather than a platform-wide switch (an RFC-scale direction change), we
**pilot one cluster** to compare operability, auth model, and monitoring in-place, fully
reversible.

`platform-db` is the lower-risk pilot: all five consumers (`auth`, `user`, `notification`,
`shipping`, `review`) are RSIP-driven (no hardcoded worker Deployments like product-db's
order/checkout workers), the `platform` namespace is outside every Kyverno policy match
list, its NetworkPolicy is simpler (`:9090` metrics-only), and Temporal already bypasses
the pooler. The product-db checkout money-path is untouched.

## Decision

Add a CNPG `Pooler` `platform-db-pooler-rw` (ns `platform`, `type: rw`,
`poolMode: transaction`, 2 instances, PodMonitor on) and remove the `pgdog-platform`
HelmRelease. Repoint the five services' `db_host`/`db_port` to
`platform-db-pooler-rw.platform.svc.cluster.local:5432`. **product-db stays on PgDog.**

- **Auth is operator-managed.** CNPG auto-creates the `cnpg_pooler_pgbouncer` role + a
  `user_search` lookup function and authenticates the pooler to the cluster with a TLS
  client certificate; PgBouncer validates each client's password via **`auth_query`**
  against `pg_shadow`. Apps keep their existing ESO-delivered `username`/`password` — no
  static user list, no `valuesFrom` password wiring, no app-cred change.
- **Port is 5432** (PgBouncer default), not PgDog's 6432 — consumers and NetworkPolicy are
  updated. Migration jobs and Temporal keep connecting **direct** to `platform-db-rw:5432`.
- `poolMode: transaction` is safe with `pkg/dbx` (SimpleProtocol + statement caches off),
  unchanged from PgDog.

## Alternatives considered

- **Keep PgDog everywhere** — status quo; no learning of the CNPG-native path, and PgDog's
  static-user model is the blocker ADR-025 works around. Not chosen (the point is to pilot).
- **Switch both clusters at once** — a platform-wide direction change → RFC-scale, larger
  blast radius, harder rollback. Deferred: pilot one, decide later.
- **`type: rw` + `type: ro` poolers with app-side read routing** — restores read-scaling
  but apps use a single `DB_HOST` today; splitting is a bigger change. Possible follow-up.

## Consequences

**Gain:** hands-on CNPG-native PgBouncer; operator-managed auth (`auth_query`, no static
password list / `valuesFrom`); a battle-tested pooler; a real PgDog-vs-PgBouncer
comparison on identical workloads.

**Accept (the cost):**
- **No read/write split on platform-db** — a single `type: rw` pooler sends everything to
  the primary; replica read-scaling PgDog gave is lost on this cluster (acceptable for the
  pilot; `type: ro` pooler is a follow-up).
- **pg_hba interaction (ADR-015).** The trailing `reject` must not block the pooler. CNPG
  adds the `cnpg_pooler_pgbouncer` auth path to its operator-managed **fixed** pg_hba
  section, above the user rules and the `reject`, so it is not blocked — **verified on the
  running cluster** as part of rollout; if ever blocked, add a `cnpg_pooler_pgbouncer`
  allow line above the reject (`platform-db/instance.yaml`).
- **Two poolers now differ** — platform-db on PgBouncer, product-db on PgDog. Operators
  must know which cluster runs which; the PgDog Grafana dashboard covers only product-db.
- **Relation to [ADR-025].** PgBouncer's `auth_query` is an alternative route to dynamic DB
  credentials (it validates whatever user exists in `pg_shadow`), distinct from PgDog
  `passthrough_auth`. If this pilot expands, the dynamic-creds direction (ADR-025) should
  be reconciled against the pooler choice.
- **Reversible.** Roll back by repointing the five `db_host`/`db_port` to
  `pgdog-platform:6432` and restoring the PgDog HelmRelease (git revert).

## Related

- [ADR-014](../ADR-014-pooler-credentials-valuesfrom/) (PgDog `valuesFrom` creds — superseded on platform-db)
- [ADR-015](../ADR-015-pg-hba-connection-isolation/) (pg_hba reject — the interaction to verify)
- [ADR-025](../ADR-025-pgdog-passthrough-dynamic-db-creds/) (dynamic creds via PgDog passthrough — auth_query is the PgBouncer counterpart)
- [`docs/databases/poolers.md`](../../../databases/poolers.md), [`architecture.md`](../../../databases/architecture.md)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-07-20 | Accepted / Not started | Decision date recorded in the header; the pilot was decided before it was applied |
| 2026-08-07 | Accepted / **Complete** | Accepted and adopted in the same change (#707), which also retired the PgDog story on `platform-db` |

---
_Last updated: 2026-08-25_
