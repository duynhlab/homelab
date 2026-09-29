# clickhouse-ddl — the ClickHouse OTel schema, as an image

The DDL the `clickhouse-schema` Job applies (`kubernetes/infra/configs/clickhouse-schema/`),
shipped as an OCI image and mounted into the Job as a read-only **image volume**
at `/sql` ([ADR-077](../../docs/proposals/adr/ADR-077-image-volume-schema-delivery/),
[RFC-0032](../../docs/proposals/rfc/RFC-0032/) Phase 2). It used to be a ConfigMap.
The image gives the schema a version identity (its digest), and a schema change
now changes the Job's pod template, so Flux re-creates the Job by itself
(`kustomize.toolkit.fluxcd.io/force: enabled` on the Job).

| | |
|---|---|
| Image | `ghcr.io/duynhlab/homelab/clickhouse-ddl`, `FROM scratch`, the five files under `/sql`, `linux/amd64` + `linux/arm64` |
| Built by | `.github/workflows/clickhouse-ddl.yml`: the pull request checks the digest, and main pushes, signs (cosign keyless) and attests |
| Reproducible | same SQL → same digest: BuildKit pinned (`moby/buildkit` by digest, in the Makefile and the workflow alike), `SOURCE_DATE_EPOCH=0`, `rewrite-timestamp=true`, no SBOM or provenance in the image itself |

## Changing the schema

1. Edit the `.sql` file(s) here.
2. `make ddl-digest` prints the new digest. Put it in the Job's image-volume
   `reference` (`kubernetes/infra/configs/clickhouse-schema/job.yaml`), in the
   same pull request.
3. The pull request fails if that digest does not match what the SQL builds to.
   On merge, CI pushes exactly that image.
4. On Kind before merging: `make ddl-load` imports the image into every node
   (`pullPolicy: IfNotPresent` then needs no registry), then `make flux-push`.

The DDL itself stays `IF NOT EXISTS` and fresh-only; see below.

## Why the schema is owned here and not by the exporter

ClickHouse schema, owned in git (RFC-0028 / ADR-065).

The otel-collector's clickhouse exporter used to create this schema itself
(create_schema: true). Two fresh Kind bring-ups proved that cannot work at
three replicas: the exporter issues CREATE ... ON CLUSTER, a host that joins
the distributed-DDL queue later SKIPS earlier entries, and IF NOT EXISTS makes
every retry a no-op. Result both times: a schema on some replicas and not
others, permanently and silently (1 of 3, then 2 of 3 after the ordering fix).
The exporter's own README recommends exactly this move:

  "While the exporter can automatically create databases and tables, it is
   recommended for production environments to manage schemas manually by
   setting create_schema to false. This approach prevents race conditions
   during startup and simplifies future upgrades. When manual schema
   management is enabled, the exporter only executes INSERT statements,
   allowing users to customize indexes, TTL, and partitioning as needed."

Two properties make this bootstrap immune to the race rather than merely less
exposed to it:

  1. The DATABASE is created per host with no ON CLUSTER, so the cluster-wide
     task queue is never involved. Measured: 0 entries in
     system.distributed_ddl_queue mentioning it.
  2. The database uses ENGINE = Replicated, so TABLE DDL run once on any one
     replica propagates through the database's own Keeper log, and a replica
     added later initialises its own tables.

The DDL below was captured with SHOW CREATE TABLE from a live cluster that the
exporter had built, then made idempotent and switched to the argument-free
engine form. It must stay column-for-column compatible with the exporter's
INSERT statements (upstream logs_insert.sql / traces_insert.sql at the pinned
collector version) — a mismatch is a runtime insert failure under traffic, not
an apply-time error, so nothing in CI would catch it.

Cold tier (2026-09-07, owner decision, no RFC). otel_logs and otel_traces
carry `TTL ... + 7 days TO VOLUME 'cold', ... + 90 days` and
`storage_policy = 'hot_cold'` (the policy lives in the CHI's
03-storage-rustfs.xml). Both tails are written in the server's normalised
form — no `DELETE` keyword, storage_policy last in SETTINGS — so SHOW CREATE
TABLE reads back exactly what this file says. otel_traces_trace_id_ts stays on
`default` on purpose: three narrow columns and the random-access lookup every
trace-by-id query starts with — putting it on S3 would cost a RustFS
round-trip per lookup for no space gain. The MV owns no storage.

Fresh-only, by decision: the CREATEs are IF NOT EXISTS and never touch a live
table, and there is no migration path. A cluster built before the tier is
rebuilt by `make up`, the same rule RFC-0028 set for the replicated rollout.
