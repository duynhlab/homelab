# ADR-015: Database connection isolation via declarative pg_hba

Close PostgreSQL's default any-role-connects-anywhere behavior on `cnpg-db`
with declarative `pg_hba` rules in the Cluster spec: one allow line per
(service role → own database) pair, then a trailing `reject` — and nothing
else.

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-07-08 | [RFC-0012](../../rfc/RFC-0012/) |

> **Don't forget: every decision is a tradeoff.** Record what you gave up, not just
> what you gained.

## Context

PostgreSQL grants `CONNECT` on every database to `PUBLIC` by default: role
`cart` could open a connection to database `order` (or `payment`) on the
shared `cnpg-db` cluster. None of the four role-management generations
RFC-0012 replaced ever addressed this, so a single leaked credential exposed
all four databases at the connection level. NetworkPolicy fences pods from
reaching the cluster, but says nothing about which *database* an
authenticated role may enter.

Two mechanics matter for the design:

- **CNPG rule placement:** user-supplied `pg_hba` entries are inserted
  *between* CNPG's fixed rules (local peer access for the instance manager
  and exporter, cert-based `hostssl` for `streaming_replica`) and its default
  permissive catch-all. A trailing `reject` therefore preempts the catch-all
  while operator, metrics, and HA replication paths stay untouched.
  `cnpg-db-replica` recovers from the object store, not streaming, so it is
  unaffected either way. `pg_hba` changes apply by **reload** — no restart.
- **Not every client speaks TLS:** payment connects direct with
  `sslmode=require`, but PgDog's upstream connections and the migration Jobs
  connect without TLS today. A `hostssl`-only rule set with a trailing
  `reject` would break every pooled service and migration on the next new
  connection.

## Decision

We will add to `Cluster.spec.postgresql.pg_hba` on `cnpg-db`:

```
hostssl payment payment all scram-sha-256
host    product product all scram-sha-256
host    cart    cart    all scram-sha-256
host    order   order   all scram-sha-256
host    all     all     all reject
```

- One allow per (role, database) pair; first match wins; everything else a
  role could try is rejected at the front door.
- `host` (matches SSL and non-SSL) for the pgdog/migration pairs; `hostssl`
  for payment, whose only client already requires TLS. Tightening the
  remaining pairs to `hostssl` is a per-line follow-up once PgDog upstream
  TLS lands.
- Source column stays `all`: pods have no stable CIDR identity worth
  encoding, and user/database matching is the isolation we're after.
- Adding a service database adds its allow line above the reject — recorded
  as the single sanctioned `instance.yaml` edit in the
  [add-a-service recipe](../../../databases/runbooks/add-service-database.md).

## Alternatives considered

- **`REVOKE CONNECT ON DATABASE … FROM PUBLIC`** — the textbook SQL fix, but
  CNPG manages no grants: it would need an out-of-band superuser Job (a new
  privileged moving part, ordering against `Database` creation, no drift
  correction) or per-service migrations (cross-repo change in every service,
  and the migration role would be revoking its own database's PUBLIC grant).
  The user decision for RFC-0012 explicitly kept P4 single-mechanism;
  layering REVOKE later remains open as defense-in-depth. Rejected here.
- **`hostssl` everywhere immediately** — stronger on paper, but breaks the
  non-TLS pgdog upstream and migration paths on day one (verified: cart/order
  run `db_sslmode: disable`). Rejected; staged tightening instead.
- **Per-source CIDR rules** — pod IPs are ephemeral and CIDR maintenance
  would rot; NetworkPolicy already owns network reachability. Rejected.
- **Do nothing (rely on NetworkPolicy only)** — leaves lateral movement open
  to any in-fence client with a leaked credential; exactly the gap RFC-0012
  scoped P4 to close. Rejected.

## Consequences

- A leaked service credential now opens exactly one database; the 4×4
  connection matrix is 4 allows + 12 rejects, verified by a scripted `psql`
  sweep at each bring-up.
- The isolation lives in Git, applies by reload, and rolls back by deleting
  five lines (CNPG regenerates the permissive default).
- **Mixed strictness is deliberate debt:** three pairs accept non-TLS until
  PgDog upstream TLS lands — the revisit trigger for tightening `host` →
  `hostssl` per pair. The `hostssl`/cert-auth end-state is researched in
  [RFC-0020](../../rfc/RFC-0020/research.md) (internal TLS on `homelab-ca`).
- `instance.yaml` gains its one sanctioned per-service edit (the HBA allow
  line), a scoped exception to ADR-013's "never touch instance.yaml".
- Superuser has no remote path (`enableSuperuserAccess` off, local peer
  only) — emergency access is `kubectl exec` into the primary pod, unchanged.

---
_Last updated: 2026-07-08_
