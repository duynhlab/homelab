# Local-stack regression blocker

Verified 2026-10-13 on macOS / Podman ARM64. This is an attempted integration
regression, not release evidence. API, browser and full telemetry gates were
not run because the dependency graph could not start.

| Configuration | Result |
|---|---|
| Fresh base + Podman + analytics + Weaver overlays | BLOCKED: review-migrate exits 1 |
| Separate fresh base Compose, no analytics overlay, same review image | Same failure reproduced |
| Database policy | Kept unchanged; no DDL grant to runtime or inherited owner privilege |

Both attempts fail before a migration is applied:

```text
ERROR: permission denied for schema public (SQLSTATE 42501)
CREATE TABLE IF NOT EXISTS "public"."schema_migrations"
```

The original review-service checkout is
`4ac3a8ba0cef17bd6a7c7ca23696abf6bf1f2c9d`. A clean archive of origin/main
`d14e06f98636521708c43838db593f02a35b746d` was also built in a temporary context,
without changing that checkout. Both fail. The latter image ID is
`sha256:2b8fe4ab082962fd7979da99d475eba813474158be982f56803e7fd0af86be96`.
Other checkouts are recorded in [regression-sources.json](./regression-sources.json).

## Cause and next change

The platform creates review_migrator with NOINHERIT and allows SET ROLE to
review_owner. Compose supplies DB_MIGRATION_ROLE=review_owner. The reviewed
service calls migratex.Run with Database.BuildDSN; the v0.39.0 migration runner
does not consume that role setting. The actual migration connection therefore
cannot create schema_migrations. Updating the service checkout alone did not
resolve this wiring gap.

The owning follow-up is review-service and, if implemented as a shared runner
option, pkg/migratex: activate the requested owner role on migration and seed
connections, keep the runtime role restricted, and test both positive and
negative privileges. Do not grant CREATE to review_runtime or loosen NOINHERIT
to make the gate green. After that fix, rebuild and rerun the complete local-stack
regression; this RFC's evidence does not substitute for it.

## Baseline reproduction

Using the same locally built review-migrate image, the temporary override was:

```yaml
services:
  review-migrate:
    image: rfc0030-phase0-review-migrate:latest
```

The tag above is a local build alias, not a published or deployment image.
The image identity and source SHA above identify what was tested.

```bash
docker-compose -p rfc0030-baseline -f local-stack/compose.yaml \
  -f /tmp/compose.baseline-review.yaml up --no-build \
  --abort-on-container-exit --exit-code-from review-migrate review-migrate
```

The baseline uses PostgreSQL 18.6 Alpine and the unchanged platform init SQL;
the analytics run uses the separately pinned Debian pg_cron candidate. The
identical failure in both isolates the migration-role issue from the overlay.
