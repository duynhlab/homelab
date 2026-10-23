# Commerce CDC qualification

Phase 0 tests the accepted [RFC-0030](./README.md) architecture before any
cluster rollout. A working Compose pipeline is not CNPG qualification.

**Source-access gap:** this executable prototype still connects PeerDB directly
to Compose PostgreSQL with TLS disabled. The accepted target is now
[pooled source access](./README.md#source-access-contract) under RFC-0029.
Do not treat these commands as the final production route or pooler evidence.
A future implementation must add the selected CDC profile, verified TLS on
both hops, credential delivery and the gates below together; do not merely
change the source hostname.

| Quick facts | Value |
|---|---|
| State | Mac prototype gates recorded; full regression blocked; Linux gates pending |
| Source | Real order, checkout and payment migrations; disposable fixture records |
| Isolation | Compose project `rfc0030-phase0`; no Flux reference |
| Transport | PeerDB v0.37.5, three database-local mirrors |
| Heartbeat | pg_cron 1.6.8, every 30 seconds, observed in ClickHouse |
| API / UI | Not implemented in Phase 0 |

## Resource naming and existing projects

Use the [RFC naming contract](./README.md#resource-naming): bucket and CDC
identity `analytics-service-cdc`, ClickHouse database `analytics`, reader
`analytics_reader`, destination peer `analytics_service`, and mirrors
`analytics_service_<source>` for order, checkout and payment. RustFS runs as
`analytics-service-cdc-storage`; bucket initialization runs as
`analytics-service-cdc-bootstrap`. Compose credentials remain disposable
fixtures, not production secret values or proof of bucket-scoped IAM.

This naming revision requires a fresh disposable `rfc0030-phase0` project and
volumes. Bootstrap includes the naming revision in its contract fingerprint
and refuses old state before changing source grants, publications or mirrors.
Archive the old evidence and explicitly retire the old disposable project
using the cleanup procedure below before starting a new run. Do not reuse its
PostgreSQL, PeerDB catalog, ClickHouse or RustFS volumes, rename a live mirror,
or drop a live replication slot to apply this change. Existing slots are not
modified; a fresh snapshot creates `peerflow_slot_analytics_service_<source>`.
Source publication names remain `analytics_<source>`.

Historical reports in issue #1266 refer to their original SHAs and names.
They do not qualify this revision. Re-run snapshot, insert/update/delete,
freshness, reader-denial, RustFS recovery and DDL recovery gates on Linux with
the new names. The API route and table names are unchanged.

## Run on Mac or Linux Compose

Use the sibling service checkouts expected by local-stack. Record their SHAs
and dirty status; do not call a dirty-tree run release evidence. On Mac, start
the existing Podman machine and use its socket:

```bash
podman machine start
export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"
```

From the homelab root, use Bash and the Compose CLI (`docker-compose` may be
replaced by `docker compose`). These commands target only the disposable project:

```bash
docker-compose -p rfc0030-phase0 -f local-stack/compose.yaml \
  -f local-stack/compose.analytics.yaml config --quiet
COMPOSE_PARALLEL_LIMIT=1 docker-compose -p rfc0030-phase0 \
  -f local-stack/compose.yaml -f local-stack/compose.analytics.yaml up -d --build \
  postgres clickhouse analytics-flow-worker analytics-snapshot-worker \
  order-migrate checkout-migrate payment-migrate
python3 local-stack/analytics/control.py bootstrap
ANALYTICS_EVIDENCE_DIR=/tmp/rfc0030-evidence make e2e-analytics GATE=compose
ANALYTICS_EVIDENCE_DIR=/tmp/rfc0030-evidence make e2e-analytics-ddl GATE=compose
```

The control command uses the fixed project, real migrations, an explicit
column allowlist, and source-schema-derived exclusions. It refuses to reuse
mirrors when that contract changes. Re-running bootstrap with the same contract
does not create extra publications, cron jobs or mirrors. Run it only against
fixture data. The local control API binds to loopback; it is not a public API.

For a cold repeat, archive evidence first, then remove **only this project**:

```bash
docker-compose -p rfc0030-phase0 -f local-stack/compose.yaml \
  -f local-stack/compose.analytics.yaml down -v
```

Do not run this cleanup against the regular local-stack project. Existing host
ports must be free; project isolation does not isolate host port bindings.

## Artifact and compatibility contract

Image digests are pinned in the [Compose overlay](../../../../local-stack/compose.analytics.yaml);
pg_cron package checksums are pinned in its [Dockerfile](../../../../local-stack/analytics/postgres/Dockerfile).

- Core source: tag `v0.37.5`, commit `053ba64d0ec492438977d4e2bbe5f7b511aeb6ba`.
- Chart: `v0.9.16`, commit `68ffa1449384d155ea03d3676c8be44d294833d4`; its
  default app is v0.36.26. Qualification overrides every enabled component to
  the v0.37.5 digest from the Compose overlay.
- The exploratory Helm 3 render is **not deployment-ready**: the upstream worker templates lack probes
  and explicit object namespaces, and cluster Secrets, staging configuration,
  network controls and admission must be supplied and tested on Linux.
- The catalog schema is initialized by the matching `peerdb-server` image's
  migrations-only command before workers start. Existing Temporal is reused
  with a dedicated `peerdb` namespace and `MirrorName` search attribute.
- CNPG image recipe belongs to `duynhlab/images`, `images/postgresql-cron`.
  Both it and the Compose recipe pin base digests and the AMD64/ARM64 PGDG
  `postgresql-18-cron` package payloads by SHA-256. Payload extraction avoids an
  accidental PostgreSQL upgrade; dpkg does not register this extracted package.
- Compose uses PostgreSQL 18.6 Debian's standard entrypoint. CNPG uses the 18.6
  system image. Their build and runtime evidence must remain separate.
- Snapshot staging is retained in the disposable bucket for inspection with
  `PEERDB_CLICKHOUSE_SKIP_STAGING_CLEANUP=true`. This is an audit setting, not
  a production retention policy. Delete the project after evidence is archived.

### Reproduce the artifact checks

From the homelab root:

```bash
make -C ../images lint IMAGE=postgresql-cron
make -C ../images digest IMAGE=postgresql-cron
```

Use the image repository's Make targets so the pinned builder and normalization
are retained; do not publish the candidate manually. Record the resulting digest
and tested commit in the [Linux handoff issue](https://github.com/duynhlab/homelab/issues/1266).
The exploratory chart values are not a supported deployment configuration;
Linux qualification must supply and verify the cluster configuration.

### License disposition

This prototype runs unmodified PeerDB privately and does not expose PeerDB
features as a hosted service. Core carries AGPL-3.0; the chart carries ELv2.
Preserve upstream notices. Distribution, modifications, or exposing PeerDB to
third parties require rechecking the relevant obligations. This source review
does not claim general legal approval or close the rollout license gate.

## Findings from the first runtime pass

Repository and Compose inspection on 2026-10-13:

1. Temporal namespace creation can return before its frontend cache observes
   the namespace. Bootstrap waits for search-attribute access with a timeout.
2. `PEERDB_NULLABLE` defaults to false on the pinned build. The first run mapped
   a PostgreSQL NULL `completed_at` to the epoch. New mirrors explicitly enable
   it; a configuration change requires fresh mirrors, not reuse of old tables.
3. PeerDB backs off after CDC errors: ordinary failures wait one to ten
   minutes, increasing with recent errors. Sequential outage tests can take
   longer to recover than an isolated restart. The gate keeps its explicit
   deadlines and records failures rather than treating a running container as
   proof of catch-up.
4. Serving views read `FINAL` over PeerDB's `ReplacingMergeTree(_peerdb_version)`
   and filter tombstones afterwards: the whole highest-version row, NULLs
   included. The first shape, one `argMax(tuple(...), _peerdb_version)` per id,
   had the same semantics but recomputed a full `GROUP BY` on every read and
   cost the whole 2 s budget at one million ledger facts
   ([analytics-service#4](https://github.com/duynhlab/analytics-service/issues/4)).

5. A normal ClickHouse view without explicit SQL security requires the reader
   to access the raw table. Serving views now use `SQL SECURITY DEFINER` with
   a separate `HOST NONE` owner granted SELECT on the exact raw tables. The
   consumer receives only view SELECT. The gate checks successful view reads
   and rejected raw reads/writes.

6. Mirror termination must request `STATUS_TERMINATING`. On the pinned core,
   the HTTP handler accepts `STATUS_TERMINATED`, but the active CDC workflow
   does not consume that as a termination command. The first DDL attempt timed
   out; the corrected gate waits for catalog removal and source-slot removal.

7. PostgreSQL also rejects a mapped column's type change while its publication
   depends on that column. With the scratch mirror stopped and its slot removed,
   the DDL gate temporarily narrows the publication to the primary key, changes
   the schema, then installs the new column contract before resnapshotting.

These are prototype findings, not evidence of a cluster incident.

The DDL gate copies two columns from `order_items` into a scratch table, with
its own restricted source role and temporary mirror. It pauses and deliberately
terminates that mirror before changing the source contract, retains raw
evidence, and creates a new snapshot after adding an excluded column, changing
`product_name` from varchar to text, and dropping that mapped column. It checks
identity, values and exclusion of the new PII fixture column. It does not prove
automatic schema propagation or a production resync RTO; repeating this gate
requires a fresh disposable project.

## Verification records

Test results, machine-specific inventories and handoff status belong in
[issue #1266](https://github.com/duynhlab/homelab/issues/1266), not in the source
tree. Keep generated reports outside the checkout using `ANALYTICS_EVIDENCE_DIR`
and attach evidence to the owning verification record.

The Mac prototype used small native ARM64 fixtures. It does not qualify CNPG,
capacity or release readiness. Full local-stack regression is blocked by the
review-service migration connection not activating its configured owner role;
the issue records the baseline reproduction and required follow-up. Preserve
NOINHERIT and restricted runtime privileges when fixing that wiring.

## Linux handoff gates

| Gate | Required evidence | State |
|---|---|---|
| Image supply chain | Two clean builds, scan, signed release and exact digest | Pending; no release published |
| CNPG image lifecycle | Library load, activation, restored backup, rollback, every instance compatible | Pending |
| Scheduler promotion | Primary-only execution after switchover/failover; job/history/worker bounds | Pending |
| Source access | Qualified primary-only pooler for snapshot SQL and replication; verify-full both hops; exact HBA/grants and Publication `status.applied` | Pending; direct plaintext Compose baseline is not evidence |
| Pooler lifecycle | Concurrent snapshot writes, exported snapshot/parallel readers, streaming keepalives, restart/drain, reconnect, primary promotion, slot/offset recovery and retained-WAL bounds | Pending; #1305 blocks cutover |
| Consumer slots | Resume without gaps or explicit resync through promotion and WAL invalidation | Pending |
| Kubernetes boundary | Secrets, NetworkPolicy, resource/probe/admission checks, Flux ordering | Pending |
| DDL evolution | Add/drop/type changes and recovery on the pinned build | Pending |
| Failure coverage | API/catalog/Temporal and network outages, large transactions, WAL invalidation/resync | Pending; Compose covers worker restart and short RustFS/ClickHouse interruptions only |
| Credential lifecycle | New password accepted and old password refused on fresh connections; stream recovers at verified offset; wrong CA/hostname and plaintext denied on both hops; CA overlap/reload | Pending; Compose uses disposable identities |
| Data exclusion | Trace payload inspection and wider representative PII fixtures | Pending; Compose inspects allowlisted raw/staging data and PeerDB logs |
| Native capacity | Full snapshot, WAL/staging bounds, one million facts; 7/30/90-day checksums | Pending |
| Query performance | p95 ≤500 ms, peak memory ≤512 MiB, no pod restart | Pending |
| License | Explicit pre-rollout disposition for actual use/distribution | Pending |

Do not enable the gateway/Admin route or mark Phase 0 qualified until every
mandatory gate has evidence. Analytics API behavior and browser acceptance
belong to later phases; this prototype does not implement their endpoints.

## References

- [Research](./research.md) and [accepted RFC](./README.md)
- [Upstream core v0.37.5](https://github.com/PeerDB-io/peerdb/releases/tag/v0.37.5)
- [Chart v0.9.16](https://github.com/PeerDB-io/peerdb-enterprise/releases/tag/v0.9.16)
- [ClickHouse view SQL security](https://clickhouse.com/docs/reference/statements/create/view#sql-security)
- [ClickHouse user host restrictions](https://clickhouse.com/docs/reference/statements/create/user)
- [Versioned CDC retry behavior](https://github.com/PeerDB-io/peerdb/blob/v0.37.5/flow/workflows/cdc_flow.go)
- [Versioned dynamic settings](https://github.com/PeerDB-io/peerdb/blob/v0.37.5/flow/internal/dynamicconf.go)
- [Versioned core license](https://github.com/PeerDB-io/peerdb/blob/v0.37.5/LICENSE)
- [Versioned chart license](https://raw.githubusercontent.com/PeerDB-io/peerdb-enterprise/68ffa1449384d155ea03d3676c8be44d294833d4/LICENSE.md)
