# CDC / analytics / cache

The commerce CDC pipeline (PeerDB → ClickHouse), the analytics read model it
feeds, and the Valkey cache.

## Authoritative docs

- Commerce CDC (components, operations, drills, alerts):
  [databases/cdc/README.md](../../../../../docs/databases/cdc/README.md).
- Analytics read model + freshness: [api/analytics.md](../../../../../docs/api/analytics.md),
  [observability/analytics/](../../../../../docs/observability/analytics/README.md).
- ClickHouse day-2 + alerts: [clickhouse/operations.md](../../../../../docs/observability/clickhouse/operations.md),
  [clickhouse runbooks](../../../../../docs/observability/runbooks/clickhouse/README.md).
- Cache (Cache-Aside, eviction): [caching/README.md](../../../../../docs/caching/README.md),
  [api/caching.md](../../../../../docs/api/caching.md);
  [valkey runbooks](../../../../../docs/observability/runbooks/valkey/README.md).

## Manifests

- CDC: `kubernetes/infra/configs/cdc/` (PeerDB, CDC pooler, pg_cron heartbeats).
- ClickHouse: `kubernetes/infra/configs/observability/` (Keeper, schema DDL Job).

## Diagnose

```bash
scripts/analytics/cdc-source-check.sh      # publication, slot, pooler on the source
scripts/analytics/cdc-target-check.sh      # mirror + target ingestion
scripts/analytics-freshness-drill.sh       # end-to-end freshness
scripts/analytics/cdc-drills.sh
```

- Analytics freshness incidents span **CDC mirror → ClickHouse load → serving
  view**: confirm which hop is behind (slot lag, mirror, target ingest) before
  blaming the analytics service.
- A `validation` reason needs serving-view/ledger investigation; `limits` needs
  capacity. Do not widen grants or log returned rows to investigate.
- CDC is a logical-replication consumer of `product-db`; a replication-slot or
  heartbeat symptom is also a [PostgreSQL](data-postgresql.md) concern.

## Boundary

CDC alerts live in the alert catalog (§ CDC) and the `postgresql`/`clickhouse`
runbook folders, not a dedicated `cdc/` runbook tree — route accordingly and
report that split as a gap if it blocks you.
