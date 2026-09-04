# Schema and queries — one junior skill on the live `otel_*` tables

Design the **sort key**, prove the query **prunes granules**, then look at
**codecs**. One loop, real DDL from git — not a new OTel schema. The Collector
exporter **INSERT**s a fixed column list; changing names or dropping columns
breaks ingest.

| | |
|---|---|
| **Skill** | `ORDER BY` prefix → `EXPLAIN indexes = 1` → codecs last |
| **Tables** | `otel.otel_logs`, `otel.otel_traces` (DDL in `kubernetes/infra/configs/clickhouse-schema/configmap-schema.yaml`) |
| **Why ClickHouse exists next to VictoriaLogs** | LogsQL finds a line. This store is for **GROUP BY**, percentiles, and `TraceId` correlation over 90 days — [fundamentals](fundamentals.md) |
| **Hands-on** | Hub [Playground §3](README.md#3-see-the-sparse-index-prune-granules) |

---

## Overview

DevOps lore says the hard parts are schema, codecs, and queries. They are
**one** skill: the schema is the query you can afford, and codecs only matter
after the scan is already small.

**Postgres analog:** a B-tree can seek to a key. MergeTree's primary index is
**sparse** — one mark per granule (~8192 rows), from the `ORDER BY`. Ask:
*does this WHERE match the sort prefix so granules can be skipped?* If
`EXPLAIN` says `Granules: b/b`, you are scanning. Fix the filter (or accept
that this lookup needs a skip index / [MV](materialized-views.md)), **then**
look at compression.

Kind is not marketplace scale. The prune **principle** is identical; the row
count is not.

Do **not** invent replacement OTel tables. The exporter contract is the
column list in that ConfigMap.

---

## 1. Schema = `ORDER BY` prefix

The columns you filter **most** belong at the **left** of `ORDER BY`. Later
keys only help after earlier keys are equality (or a tight range).

### Logs — time buckets then service

Deployed `otel_logs`:

```sql
ORDER BY (toStartOfFiveMinutes(Timestamp), ServiceName, Timestamp)
PARTITION BY toDate(Timestamp)
```

Dashboards filter a **time window** and often a **service**. The five-minute
bucket is the first sparse-index key so a dashboard range can skip granules
that fall in other buckets; `ServiceName` is next so a service filter inside
that window is still cheap. A filter that matches neither prefix (random map
key, no time bound) will scan.

Junior rule: *the column you filter most often stands first — unless time
pruning is the actual first cut, as it is on logs.*

### Traces — service then span name then time

Deployed `otel_traces`:

```sql
ORDER BY (ServiceName, SpanName, toDateTime(Timestamp))
```

Service-first matches Grafana "this service's traces" and error-rate
`GROUP BY ServiceName`. A lookup of **one `TraceId` is not a primary-key
lookup**. That is why the table also has `INDEX idx_trace_id TraceId TYPE
bloom_filter(0.001)` and the compact
`otel_traces_trace_id_ts` table populated by an incremental MV — see
[materialized-views](materialized-views.md).

### Skip indexes vs projections

Skip indexes (bloom, minmax, `text()` on logs) prune extra columns without a
second sort. **Projections** would store another `ORDER BY`; this cluster
does not use them.

---

## 2. Query = `EXPLAIN indexes = 1`

Read **`Granules: a/b`**. `b/b` means the primary (and listed skip) indexes
did not cut the scan. Add the sort prefix to `WHERE`, then run EXPLAIN
again.

Connect: [Playground](README.md#connect). Always know **which replica**
answered — `system.*` is local.

### Traces — service prefix (cheap)

Copied from the hub playground (live local-stack shape):

```sql
EXPLAIN indexes = 1
SELECT count() FROM otel.otel_traces
WHERE ServiceName = 'platform.envoy-gateway-system';
```

Expect `PrimaryKey` on `ServiceName` and `Granules` much smaller than the
total. `platform.envoy-gateway-system` is the edge `service.name` as Envoy
Gateway derives it (`<gateway>.<namespace>`) — environment-dependent.

Now drop the service filter (or filter only `TraceId`) and compare granules.
The bloom index may still skip some parts; it is not a B-tree seek.

### Logs — add time and service, then re-EXPLAIN

```sql
EXPLAIN indexes = 1
SELECT count() FROM otel.otel_logs
WHERE Timestamp > now() - INTERVAL 1 HOUR;

EXPLAIN indexes = 1
SELECT count() FROM otel.otel_logs
WHERE Timestamp > now() - INTERVAL 1 HOUR
  AND ServiceName = 'platform.envoy-gateway';
```

`toDate(Timestamp)` is also the **partition** key: a day bound can skip
whole partitions before granules. Prefer a time window on every analytics
query.

### Grafana-shaped SQL (same prune rules)

From the hub [query examples](README.md#query-examples) — Explore or a
dashboard panel:

```sql
SELECT ServiceName,
       100.0 * countIf(StatusCode = 'STATUS_CODE_ERROR') / count() AS err_pct
FROM otel.otel_traces
WHERE Timestamp > now() - INTERVAL 7 DAY
GROUP BY ServiceName ORDER BY err_pct DESC;

SELECT ServiceName, SpanName, round(quantile(0.95)(Duration)/1e6, 2) AS p95_ms
FROM otel.otel_traces
GROUP BY ServiceName, SpanName ORDER BY p95_ms DESC LIMIT 20;
```

Prefix `EXPLAIN indexes = 1` on the same `FROM`/`WHERE`. A missing time
bound or a `GROUP BY` with no `ServiceName` filter is a larger scan — that
can still be the right question; know the cost.

Edge access-log mix (LogsQL cannot do this; this is why CH exists for that
stream):

```sql
SELECT LogAttributes['status'] AS status, count() AS hits
FROM otel.otel_logs
WHERE ServiceName = 'platform.envoy-gateway'
  AND Timestamp > now() - INTERVAL 1 HOUR
GROUP BY status ORDER BY hits DESC;
```

(`TimestampTime` is **not** on the 1.3.0 logs shape this cluster writes —
use `Timestamp`.)

For `EXPLAIN` on a **TraceId** path, run it on **both**
`otel_traces_trace_id_ts` and `otel_traces` — the MV is another table, not a
Postgres index. Details: [materialized-views](materialized-views.md).

---

## 3. Codecs after the scan is clean

Do not raise `ZSTD(n)` to "fix" a full-table scan. First get `Granules: a/b`
honest, then inspect what is already on disk.

```sql
SELECT name, type, compression_codec
FROM system.columns
WHERE database = 'otel' AND table = 'otel_traces'
  AND name IN ('Timestamp', 'TraceId', 'ServiceName', 'Duration');

SELECT table,
       formatReadableSize(sum(data_compressed_bytes)) AS comp,
       formatReadableSize(sum(data_uncompressed_bytes)) AS uncomp,
       round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 1) AS ratio
FROM system.parts
WHERE database = 'otel' AND active
GROUP BY table;
```

`Timestamp` already uses `CODEC(Delta(8), ZSTD(1))` — deltas on a sorted
time column, then ZSTD. `LowCardinality(String)` on `ServiceName` /
`SpanName` is a dictionary, not a codec knob. Changing codecs on a live
ReplicatedMergeTree is a mutation; it is not a playground first step.

---

## How it works on this platform

| Rule | Here |
|------|------|
| Who owns DDL | `clickhouse-schema` Job; exporter `create_schema: false` |
| Who owns INSERT columns | Collector contrib `clickhouse` exporter 0.159.0 |
| Logs sort | Five-minute bucket, then service, then timestamp |
| Traces sort | Service, span name, time — not TraceId |
| Grafana | Filters that match those prefixes stay cheap; see [README Grafana](README.md#grafana) |

---

## Operations snippets

Full connect + `system.parts` recipes: [Playground](README.md#playground--mergetree-by-hand).
Vietnamese ops notes (unchanged by this learning split): [van-hanh.vi.md](van-hanh.vi.md).

---

## References

- [Schema design](https://clickhouse.com/docs/data-modeling/schema-design)
- [Choosing a primary key](https://clickhouse.com/docs/guides/best-practices/choosing-a-primary-key)
- [EXPLAIN](https://clickhouse.com/docs/sql-reference/statements/explain)
- [Column compression codecs](https://clickhouse.com/docs/sql-reference/statements/create/table#column-compression-codecs)
- [Observability schema design](https://clickhouse.com/docs/observability/schema-design)
- DDL: [`configmap-schema.yaml`](../../../kubernetes/infra/configs/clickhouse-schema/configmap-schema.yaml)
- [Fundamentals](fundamentals.md) · [Materialized views](materialized-views.md) · [Hub](README.md)

---

_Last updated: 2026-09-04_
