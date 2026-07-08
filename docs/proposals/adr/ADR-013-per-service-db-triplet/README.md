# ADR-013: Per-service database triplet on CNPG DatabaseRole CRs

Adopt one file per service under `clusters/cnpg-db/services/` — an
`ExternalSecret` + a fully-specified `DatabaseRole` + a `Database` — as the
single pattern for every service database on `cnpg-db`, replacing the inline
`managed.roles` stanza (and, in later phases, `postInitSQL`).

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-07-08 | [RFC-0012](../../rfc/RFC-0012/) |

> **Don't forget: every decision is a tradeoff.** Record what you gave up, not just
> what you gained.

## Context

`cnpg-db` accumulated four generations of role/database management — the best
tool available at the moment each service arrived: `bootstrap.initdb`
(product), `postInitSQL` with cleartext passwords in Git (cart, order), inline
`managed.roles` (payment), and `Database` CRs (extensions for all four). The
full archaeology, costs, and phased migration live in RFC-0012; the short
version is that role definitions were scattered across a shared Cluster spec
in three different shapes, two passwords sat cleartext in Git, and a
from-scratch rebuild and a backup restore converged to *different* role sets.

CNPG 1.30 (landed as RFC-0012 P0) added the missing piece: `DatabaseRole`, a
standalone namespaced CR for a single role, with its own status and lifecycle —
roles no longer have to live inline in the shared Cluster spec.

Two semantics of `DatabaseRole` shape the pattern and are worth recording with
the decision:

- **Adoption resets omitted attributes.** Creating a `DatabaseRole` for an
  existing role alters *every* attribute to match the manifest — omitted
  memberships are revoked, an omitted `connectionLimit` resets to `-1`, an
  omitted `validUntil` becomes `infinity`. Manifests must therefore be written
  out in full, and the live role's attributes snapshotted before adoption.
- **Inline precedence is the rollback lever.** If the same role name appears in
  `Cluster.spec.managed.roles`, the Cluster spec wins and the `DatabaseRole`
  reports `applied: false`. Re-adding one inline entry instantly and safely
  reverts a migrated role.

## Decision

We will define every service database on `cnpg-db` as a **triplet in one file**,
`kubernetes/infra/configs/databases/clusters/cnpg-db/services/<name>.yaml`:

1. **`ExternalSecret`** — renders a `kubernetes.io/basic-auth` Secret from
   OpenBAO (`secret/data/local/databases/cnpg-db/<name>`), labeled
   `cnpg.io/reload: "true"` so password changes apply immediately.
2. **`DatabaseRole` `cnpg-db-role-<name>`** — the service identity, written out
   in full (every attribute explicit), `validUntil` omitted on purpose (app
   identities never expire), `databaseRoleReclaimPolicy: retain`.
3. **`Database` `<name>-database`** — owned by that role, carrying the
   extension list, `databaseReclaimPolicy: retain`.

Role is declared before Database in the file: CNPG guarantees no ordering
between the two (a Database whose owner is missing fails and retries), but
role-first makes the happy path deterministic.

Placement is **centralized** in the databases tree, not next to the service's
app manifests: roles and databases are cluster-global objects owned by the
platform, and the databases Flux Kustomization reconciles before apps. Adding a
service database touches this one directory — never `instance.yaml`.

Reclaim policies are `retain` everywhere: deleting a CR must never take a
production role or database with it; dropping either stays a deliberate manual
act.

## Alternatives considered

- **Converge on inline `managed.roles`** (works on 1.29, no CRD needed) — fixes
  the cleartext-password generation but entrenches the wrong ownership
  boundary: every service edit goes through the shared Cluster spec, and the
  role definition can never live with the rest of the service's database
  resources. Rejected: the boundary is the point of this ADR.
- **Triplet next to the service's app manifests** (`kubernetes/apps/…`) —
  stronger per-service ownership story, but global DB objects would live
  outside the databases tree and reconcile in the apps Kustomization, after
  databases — inverting the real dependency. Rejected.
- **Roles/databases from each service's SQL migrations** — a bootstrap paradox
  (the migration needs the role to connect), and cluster-global objects don't
  belong to one service's migration history. Rejected.
- **`databaseRoleReclaimPolicy: delete`** for symmetry with GitOps pruning —
  rejected: a pruned or fat-fingered CR deletion must not `DROP ROLE`; and a
  role that still owns objects wedges in `Terminating` anyway (the operator
  never drops owned objects).

## Consequences

- Adding a service database becomes a one-file PR in one directory; the shared
  Cluster spec stops changing per service.
- **Reconcile model changes, accepted:** inline roles were periodically
  compared against the catalog and self-healed manual drift; a `DatabaseRole`
  re-applies only when its spec or password Secret changes. Git remains the
  source of truth; drift correction happens on the next spec/Secret change.
  Nobody should be hand-editing roles.
- **`ensure: absent` is lost:** declaratively removing a pre-existing role now
  requires a temporary inline `managed.roles` entry or manual SQL. Acceptable —
  role removal should be rare and deliberate.
- Each migrated role goes through an adoption step with a sharp edge (omitted
  attributes reset), mitigated by full-attribute manifests plus a
  before/after `pg_authid` snapshot in each migration PR.
- Rollback stays cheap while the migration runs: one inline entry re-added to
  the Cluster spec makes the old definition authoritative immediately.
- **Revisit trigger:** if CNPG later ships `DatabaseRole`-level catalog
  reconciliation or an `ensure: absent` equivalent, revisit the drift-handling
  and role-removal notes above.
