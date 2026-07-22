# ClickHouse — OTel logs+traces OLAP

Open-source columnar OLAP giving the platform **long-retention SQL over
OpenTelemetry logs and traces** — the cross-day analytics the 7-day,
LogsQL/TraceQL-only ops primaries can't, plus the `otel_logs`↔`otel_traces`
`trace_id` JOIN in one store (**RFC-0019 Phase B**).

| | |
|---|---|
| **Status** | **Deployed** — local-stack + cluster (RFC-0019 Phase B) |
| **Role** | **Supplementary** OLAP for logs+traces SQL. Runs **alongside** VictoriaLogs / Tempo / VictoriaTraces (day-to-day ops primaries), which are **unchanged** |
| **Engine** | `clickhouse/clickhouse-server:25.3`, MergeTree, single shard × single replica |
| **Operator** | Altinity `clickhouse-operator` `0.27.1` + a `ClickHouseInstallation` CR |
| **Ingest** | OTel Collector contrib `clickhouse` exporter — fan-out on the **traces + logs** pipelines (metrics stay on VictoriaMetrics — **never** here) |
| **Tables** | `otel.otel_logs`, `otel.otel_traces` (+ `otel_traces_trace_id_ts` MV), auto-created by the exporter (`create_schema`) |
| **Retention** | **TTL 90 days** (`ttl_only_drop_parts`) vs 7d on the ops primaries — the long-retention payoff |
| **Storage** | local PVC `standard` `10Gi` (cluster); ephemeral volume (local-stack) |
| **Query** | Grafana `grafana-clickhouse-datasource` (`uid: clickhouse`, native `:9000`) + the **ClickHouse — OTel logs+traces SQL** dashboard |
| **App code** | **Unchanged** — `pkg/obsx` / `pkg/grpcx` untouched; adding ClickHouse is a Collector-exporter change |
| **Design** | [RFC-0019](../../proposals/rfc/RFC-0019/) · [ADR-023](../../proposals/adr/ADR-023-clickhouse-observability-olap/) |

> **In one line:** the same OTel telemetry, a second sink. Because everything is
> instrumented with OpenTelemetry (the vendor-neutral "narrow waist"), a new
> backend is a Collector-exporter change — not an application change.

---

## Table of contents

1. [Overview](#overview)
2. [Reading path](#reading-path)
3. [What ClickHouse is](#what-clickhouse-is)
4. [Core components](#core-components)
5. [MergeTree mechanism](#mergetree-mechanism)
6. [Architecture](#architecture)
7. [How it works in this platform](#how-it-works-in-this-platform)
8. [Operations](#operations)
9. [Playground — MergeTree by hand](#playground--mergetree-by-hand)
10. [Glossary](#glossary)
11. [ClickHouse vs PostgreSQL](#clickhouse-vs-postgresql)
12. [Commerce analytics (Phase A — not deployed)](#commerce-analytics-phase-a--not-deployed)
13. [FAQ](#faq)
14. [References](#references)

---

## Overview

VictoriaLogs, Tempo, and the VictoriaTraces pilot all cap at **7-day** retention
and answer **LogsQL / TraceQL only**. There is no cross-day **SQL/OLAP** over
structured log/trace fields (errors by service over weeks, duration percentiles,
status mixes) and no way to **JOIN** logs↔traces on `trace_id` in one store. RED
metrics on VictoriaMetrics do not substitute for log/trace search.

ClickHouse fills exactly that gap as a **supplementary** backend: the OTel
Collector dual-writes logs and traces to it while the ops primaries keep running
untouched. It is **not** a replacement for CloudNativePG (OLTP source of truth)
or for the primary observability stack.

---

## Reading path

1. **Foundations** — [What ClickHouse is](#what-clickhouse-is) → [MergeTree](#mergetree-mechanism) → [vs PostgreSQL](#clickhouse-vs-postgresql)
2. **This platform** — [Architecture](#architecture) → [How it works here](#how-it-works-in-this-platform)
3. **Use it** — [Operations](#operations) → [Playground](#playground--mergetree-by-hand)
4. **Lookup** — [Glossary](#glossary) · [FAQ](#faq)

Pair with [`docs/databases/001-postgresql-internals.md`](../../databases/001-postgresql-internals.md)
if you already know Postgres heap / WAL / B-tree.

---

## What ClickHouse is

**ClickHouse** is an open-source **OLAP** (Online Analytical Processing) database
built for aggregation over huge row counts, time-series/event analytics, and
near-real-time dashboards after append ingest. It is **not** a replacement for
PostgreSQL orders, payments, or user accounts — those are **OLTP** workloads on
CNPG (`product-db`, `platform-db`).

### OLAP vs OLTP

| | OLTP (PostgreSQL) | OLAP (ClickHouse) |
|---|---|---|
| Typical question | "Order #123 for user X?" | "Error rate by service over 30 days?" |
| Write pattern | Frequent UPDATE/DELETE, ACID | Append INSERT, read-heavy aggregation |
| Indexing | B-tree on heap | Sparse index on sort key + skipping indexes |
| Read scale | Point lookup, moderate joins | Column scans, large aggregations |

> **In plain terms:** aggregation folds many rows into a few meaningful numbers —
> `COUNT` failures by service, `quantile` latency by operation. OLTP answers
> *"what is this row?"*; OLAP answers *"how does the whole set look?"*.

### Columnar storage

PostgreSQL is **row-oriented** (a page holds many columns of one row). ClickHouse
is **column-oriented** (each column is its own file inside a **part**).
`SELECT ServiceName, count()` reads only the `ServiceName` column files — and
compresses them hard because a column holds like values (see the **10.5×**
compression measured [below](#operations)).

```mermaid
flowchart LR
  subgraph rowStore ["PostgreSQL — row pages"]
    Page["8KB page<br/>all columns of a row together"]
  end
  subgraph colStore ["ClickHouse — column files in a part"]
    C1["ServiceName file"]
    C2["Duration file"]
    C3["Timestamp file"]
  end
  Q["SELECT ServiceName, count()"] --> C1
```

---

## Core components

| Piece | Role |
|-------|------|
| **clickhouse-server** | Query engine + storage (native TCP `:9000`, HTTP `:8123`) |
| **clickhouse-operator** | Altinity operator; reconciles a `ClickHouseInstallation` CR into a StatefulSet |
| **Table engine** | Storage semantics — **MergeTree** is the analytics default |
| **Part** | Immutable on-disk chunk produced by an insert batch |
| **Granule** | ~8192-row read unit; the sparse index points at the first row of each granule |
| **Materialized view** | Here, `otel_traces_trace_id_ts` — a trace-id→time-range index for fast single-trace lookup |

---

## MergeTree mechanism

MergeTree is **not** a Postgres B-tree row store.

| | PostgreSQL B-tree | ClickHouse MergeTree |
|---|---|---|
| Primary purpose | Point lookup / range on heap | Sort + prune granules for scans |
| Write path | Update pages / WAL | Append new **parts** |
| Background | Autovacuum / checkpoints | **Merges** combining parts |

**Insert → part → merge:**

```mermaid
flowchart LR
  I1["INSERT batch"] --> P1["Part 1"]
  I2["INSERT batch"] --> P2["Part 2"]
  P1 & P2 --> Merge["Background merge"]
  Merge --> PMerged["Larger part<br/>same sort order"]
```

The sparse primary index stores **one entry per granule** (the first row's sort
key), not a row-level index. Skipping indexes (minmax, set, bloom) are optional
secondary pruning. This is exactly what the deployed `otel_traces` table uses —
see its **real DDL** in [Operations](#operations) and watch pruning happen in the
[Playground](#playground--mergetree-by-hand).

---

## Architecture

The Collector fans telemetry out to every backend in parallel. ClickHouse is the
4th trace sink and the 2nd log sink; a failure there cannot stall the ops
primaries (`sending_queue` + `retry_on_failure` isolate it).

```mermaid
flowchart LR
  Apps["10 services + 2 workers<br/>+ Kong"] -->|OTLP| Col["OTel Collector<br/>(contrib)"]
  Col -->|metrics| VM[("VictoriaMetrics")]
  Col -->|logs| VL[("VictoriaLogs")]
  Col -->|traces| Tempo[("Tempo")]
  Col -->|traces| Jae["Jaeger"]
  Col -->|traces| VT[("VictoriaTraces")]
  Col -->|"logs + traces (RFC-0019)"| CH[("ClickHouse<br/>otel_logs / otel_traces")]
  CH --> Graf["Grafana<br/>clickhouse datasource"]

  classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
  classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
  classDef collector fill:#a5d8ff,color:#111,stroke:#1971c2;
  class Apps service;
  class Col collector;
  class VM,VL,Tempo,VT,CH data;
```

**Logs-first analytics.** Traces are head-sampled (10% prod / 100% local), so
`otel_traces` counts undercount real traffic; `otel_logs` is **100% unsampled**
and is the counting workhorse. Traces are exemplars joined back on `trace_id`.

---

## How it works in this platform

| Aspect | Detail |
|--------|--------|
| **Engine** | `clickhouse/clickhouse-server:25.3`, MergeTree, 1 shard × 1 replica |
| **Operator** | Altinity `altinity-clickhouse-operator` `0.27.1` (HelmRelease in the `controllers` wave, ns `monitoring`); CRDs health-checked before the CHI applies (`kubernetes/infra/controllers/clickhouse-operator/`) |
| **Instance** | `ClickHouseInstallation` `clickhouse` (cluster `otel`) → StatefulSet `chi-clickhouse-otel-0-0`; own Flux Kustomization `clickhouse-local` `dependsOn [controllers-local, secrets-local]` (`kubernetes/infra/controllers/clickhouse/`) |
| **Storage** | PVC `standard` `10Gi` (`volumeClaimTemplates`); local-stack uses an ephemeral `clickhouse-data` volume |
| **Credentials** | `default` user password from OpenBAO `secret/local/infra/clickhouse/admin` via the `clickhouse-credentials` `ClusterExternalSecret` → Secret in `monitoring` (selector label `platform.duynhlab/clickhouse`); local-stack uses an inline dev password |
| **Ingest** | Collector contrib `clickhouse` exporter appended to the `traces` + `logs` pipelines; `create_schema: true` bootstraps the tables; `ttl: 2160h` (90d); `async_insert`, `sending_queue`, `retry_on_failure`; password via `${env:CLICKHOUSE_PASSWORD}` (`extraEnvs` secretKeyRef) |
| **Security** | `runAsNonRoot`, `runAsUser: 101`, `fsGroup: 101`, `allowPrivilegeEscalation: false`, drop `ALL` caps, `seccompProfile: RuntimeDefault`; `/ping` liveness+readiness; pinned image (PSS-baseline + no-latest) |
| **Access** | Grafana datasource `uid: clickhouse` (`clickhouse-clickhouse.monitoring.svc.cluster.local:9000`, native, password via `valuesFrom`); **not** on any public Ingress; the `default` password is the access control (no NetworkPolicy — `monitoring` has no default-deny and netpol is inert on kindnet; a `:9000`/`:8123` NetworkPolicy is a follow-up for an enforcing CNI) |
| **Startup ordering** | The collector's clickhouse exporter runs `CREATE DATABASE/TABLE` in `start()` (`create_schema`), so an unreachable ClickHouse fails the **whole** collector at startup. Ordered ClickHouse-first: local-stack via `depends_on: service_healthy`, cluster via `tracing-local dependsOn clickhouse-local`. `sending_queue`/`retry` isolate only *runtime* backpressure |
| **Dashboard** | *ClickHouse — OTel logs+traces SQL* (`uid: clickhouse-otel-sql`) — provisioned to local-stack (file) and the cluster (`configMapGenerator` → `GrafanaDashboard configMapRef`) |
| **local-stack** | `clickhouse` compose service (`:8123` HTTP, `:9000` native), collector `clickhouse` exporter, Grafana plugin + provisioned datasource; e2e audit check **C6** (`SELECT count() FROM otel.otel_traces/otel_logs`) |

The Collector's other sinks are untouched: VictoriaLogs/Tempo/Jaeger/VictoriaTraces
keep receiving, and the metrics pipeline never routes to ClickHouse.

---

## Operations

### Deployed schema (real DDL)

The contrib exporter created this — note the sort key, day-partitioning, 90-day
TTL, per-column codecs, and skipping indexes:

```sql
CREATE TABLE otel.otel_traces
(
    `Timestamp` DateTime64(9) CODEC(Delta(8), ZSTD(1)),
    `TraceId` String CODEC(ZSTD(1)),
    `ServiceName` LowCardinality(String) CODEC(ZSTD(1)),
    `SpanName` LowCardinality(String) CODEC(ZSTD(1)),
    `Duration` UInt64 CODEC(ZSTD(1)),
    `StatusCode` LowCardinality(String) CODEC(ZSTD(1)),
    -- … ResourceAttributes / SpanAttributes maps, Events.*, Links.* …
    INDEX idx_trace_id TraceId TYPE bloom_filter(0.001) GRANULARITY 1,
    INDEX idx_duration Duration TYPE minmax GRANULARITY 1
)
ENGINE = MergeTree
PARTITION BY toDate(Timestamp)
ORDER BY (ServiceName, SpanName, toDateTime(Timestamp))
TTL toDateTime(Timestamp) + toIntervalDay(90)
SETTINGS index_granularity = 8192, ttl_only_drop_parts = 1;
```

- **`ORDER BY (ServiceName, SpanName, …)`** — the sparse index; filtering by
  `ServiceName` prunes granules (proven in the [Playground](#playground--mergetree-by-hand)).
- **`PARTITION BY toDate(Timestamp)`** + **`ttl_only_drop_parts = 1`** — TTL drops
  whole day-partitions, so 90-day expiry is a cheap `DROP PARTITION`, not a rewrite.
- **`bloom_filter` on `TraceId`** + the `otel_traces_trace_id_ts` materialized view
  make single-trace lookups fast despite the service-first sort key.

### Retention & compression

| Table | Retention | Measured compression (local-stack) |
|-------|-----------|-----------------------------------|
| `otel_traces` | 90d | **10.5×** (1.20 MiB → 117 KiB) |
| `otel_logs` | 90d | **8×** (2.06 MiB → 262 KiB) |

Retention is **90 days** here vs **7 days** on VictoriaLogs/Tempo — the reason
ClickHouse exists on this platform.

### Query examples

Run from Grafana Explore (datasource **ClickHouse**) or `clickhouse-client`:

```sql
-- Error rate by service, last 7 days (SQL the ops primaries can't express)
SELECT ServiceName,
       100.0 * countIf(StatusCode = 'STATUS_CODE_ERROR') / count() AS err_pct
FROM otel.otel_traces
WHERE Timestamp > now() - INTERVAL 7 DAY
GROUP BY ServiceName ORDER BY err_pct DESC;

-- p95 latency by operation
SELECT ServiceName, SpanName, round(quantile(0.95)(Duration)/1e6, 2) AS p95_ms
FROM otel.otel_traces GROUP BY ServiceName, SpanName ORDER BY p95_ms DESC LIMIT 20;

-- Cross-signal: correlate logs to traces on trace_id (one store, one query)
SELECT t.ServiceName AS service,
       count(DISTINCT t.TraceId) AS traces,
       count(l.TraceId)          AS correlated_logs
FROM otel.otel_traces t
ANY LEFT JOIN otel.otel_logs l ON t.TraceId = l.TraceId
WHERE t.TraceId != '' GROUP BY service ORDER BY traces DESC;
```

### Dashboard

*ClickHouse — OTel logs+traces SQL* (folder **Observability**) ships the RED /
golden-signals view: span/log rate, error rate %, p50/p95/p99 latency, spans by
service, span-kind / status / severity distributions, top operations by p95, the
`trace_id` JOIN, and recent warn+ logs. `$ds` + `$service` template variables;
adaptive time bucketing.

*ClickHouse — Service deep dive* (`uid: clickhouse-service-deepdive`) drills into **one
service** at a time: per-operation RED, HTTP route / gRPC method tables (semconv v1.41
keys), east-west dependency tables, slowest/error spans with TraceId→Explore data links,
and severity-filtered logs.

The **standard suite** adds the three-tier navigation — *OTel — Overview*
(`clickhouse-otel-overview`, which service is in trouble?) → *Logs Explorer*
(`clickhouse-logs-explorer`, what errors?) → *Trace Explorer*
(`clickhouse-traces-explorer`, which span broke? — with an in-dashboard trace
waterfall + logs-for-this-trace panel). See
[grafana.md § The standard dashboard suite](./grafana.md#the-standard-dashboard-suite--overview--logs--traces).

Deep dive — datasource OTel mapping, schema versions (1.2.9 vs 1.3.0), Explore
logs/traces, trace↔log linking, dashboard grammar and macros:
[**Grafana on ClickHouse**](./grafana.md).

### Runbook — data not appearing

1. **Drive traffic**, then wait **~30–45s** (OTLP export + batch lag).
2. Collector export errors: `otelcol_exporter_send_failed_*` for the `clickhouse`
   exporter, or `kubectl logs -n monitoring deploy/otel-collector | grep -i clickhouse`.
3. ClickHouse reachable? `SELECT 1` (see [Playground](#playground--mergetree-by-hand)).
4. Tables exist? `SHOW TABLES FROM otel` — the exporter creates them on first write
   (`create_schema: true`); a wrong password blocks `CREATE DATABASE`.
5. VictoriaLogs/Tempo still receiving? They are independent sinks — ClickHouse being
   down must not affect them (`sending_queue` isolates backpressure).

---

## Playground — MergeTree by hand

Explore the **live** engine. All output below is from the running local-stack
instance — reproduce it to see MergeTree's write→part→merge→TTL lifecycle.

### Connect

```bash
# local-stack — HTTP (:8123) or interactive client (:9000)
curl -s 'http://localhost:8123/' -u default:otel --data-binary 'SELECT version()'
docker compose exec clickhouse clickhouse-client --password otel

# cluster — exec into the operator-managed pod
PW=$(kubectl get secret -n monitoring clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -it -n monitoring chi-clickhouse-otel-0-0-0 -- clickhouse-client --password "$PW"
```

### 1. Parts, rows, and compression

```sql
SELECT table, count() AS parts, sum(rows) AS rows,
       formatReadableSize(sum(data_compressed_bytes))   AS comp,
       formatReadableSize(sum(data_uncompressed_bytes)) AS uncomp,
       round(sum(data_uncompressed_bytes)/sum(data_compressed_bytes),1) AS ratio
FROM system.parts WHERE database='otel' AND active GROUP BY table;
```
```
┌─table───────┬─parts─┬─rows─┬─comp───────┬─uncomp───┬─ratio─┐
│ otel_logs   │     5 │ 8328 │ 262.59 KiB │ 2.06 MiB │     8 │
│ otel_traces │     1 │ 4287 │ 117.09 KiB │ 1.20 MiB │  10.5 │
└─────────────┴───────┴──────┴────────────┴──────────┴───────┘
```
Each INSERT batch from the Collector becomes a **part**; background **merges**
combine them (here `otel_traces` has already merged down to a single active part).
Columnar + ZSTD gives 8–10× compression.

### 2. Watch merges happen

```sql
-- how many background merges have run recently
SELECT count() FROM system.part_log
WHERE database='otel' AND event_type='MergeParts' AND event_time > now() - 3600;
-- → 1431

-- force it yourself and re-check part count
OPTIMIZE TABLE otel.otel_logs FINAL;
SELECT count() FROM system.parts WHERE database='otel' AND table='otel_logs' AND active;
```

### 3. See the sparse index prune granules

```sql
EXPLAIN indexes = 1
SELECT count() FROM otel.otel_traces WHERE ServiceName = 'kong';
```
```
ReadFromMergeTree (otel.otel_traces)
Indexes:
  PrimaryKey
    Keys:  ServiceName
    Condition: (ServiceName in ['kong', 'kong'])
    Parts: 1/5          -- 4 parts skipped outright
    Granules: 1/5       -- only 1 granule read
```
Because `ServiceName` is the first `ORDER BY` key, ClickHouse reads **1 of 5
granules** instead of scanning everything — the payoff of the sort key.

### 4. Inspect partitions & TTL

```sql
SELECT partition, count() AS parts, min(min_time) AS oldest, max(max_time) AS newest
FROM system.parts WHERE database='otel' AND table='otel_traces' AND active
GROUP BY partition;
-- one partition per day (PARTITION BY toDate(Timestamp)); TTL 90d drops whole
-- partitions (ttl_only_drop_parts = 1) — cheap, no row rewrite.
```

### 5. The trace_id materialized view

```sql
SHOW CREATE TABLE otel.otel_traces_trace_id_ts_mv;
-- MATERIALIZED VIEW … AS SELECT TraceId, min(Timestamp) AS Start, max(Timestamp) AS End
-- FROM otel.otel_traces WHERE TraceId != '' GROUP BY TraceId
-- → a compact TraceId → time-range index so single-trace lookups don't scan the
--   service-sorted main table.
```

> **Safe to experiment:** local-stack storage is ephemeral. `CREATE TABLE playground …`,
> insert rows, `OPTIMIZE`, and `DROP` freely — you cannot hurt the ops primaries.

---

## Glossary

| Term | Meaning |
|------|---------|
| **Part** | Immutable insert batch on disk |
| **Merge** | Background job that combines parts |
| **Granule** | Default ~8192-row read block |
| **Sparse index** | Index of first-row keys per granule (from `ORDER BY`) |
| **Skipping index** | Extra prune aid (minmax / set / bloom) |
| **Materialized view** | Incrementally maintained derived table (here: `trace_id` index) |
| **TTL** | Time-based expiry; here drops whole day-partitions |
| **CHI** | `ClickHouseInstallation` — the Altinity operator's CR |

---

## ClickHouse vs PostgreSQL

| Dimension | PostgreSQL (deployed) | ClickHouse (deployed) |
|-----------|----------------------|----------------------|
| Workload | OLTP — orders, users, payments | OLAP — OTel logs/traces SQL |
| Consistency | Full ACID | OLAP tradeoffs; not a source of truth |
| Updates | First-class | Prefer append; mutations are expensive |
| Joins | Strength | Prefer denormalized; `trace_id` JOIN is the key use here |

**Where each belongs on this platform:**

| Need | Store |
|------|-------|
| Order/payment source of truth | PostgreSQL (`product-db` / `platform-db`) |
| RED metrics, alerting | VictoriaMetrics |
| Live ops log/trace triage | VictoriaLogs / Tempo |
| Long-retention SQL on OTel logs/traces, `trace_id` JOIN | **ClickHouse** |

---

## Commerce analytics (Phase A — not deployed)

RFC-0019 also sketched an **optional** Phase A: batch-sync read-only commerce
facts (orders, payments, checkout sessions) from Postgres into ClickHouse fact
tables for GMV / funnel panels. **This is out of scope for the current
implementation** (observability-only) and is **not deployed**. If revived it would
be a nightly batch SQL export from `product-db` / `platform-db` via PgDog — never
CDC, never new public analytics APIs, and Postgres stays authoritative. See
[RFC-0019](../../proposals/rfc/RFC-0019/).

---

## FAQ

**Does this replace VictoriaLogs / Tempo?**
No. They remain the day-to-day ops primaries; ClickHouse is supplementary
long-retention SQL. All backends run in parallel by design.

**Does adding ClickHouse change any service code?**
No. `pkg/obsx` / `pkg/grpcx` are untouched; it is a Collector-exporter change.

**Do metrics go to ClickHouse?**
Never. Metrics stay on VictoriaMetrics; only the traces + logs pipelines fan out here.

**Why do trace counts look low?**
Traces are head-sampled (10% prod). Use `otel_logs` (100%) for counting; treat
`otel_traces` as exemplars joined on `trace_id`.

**Can ClickHouse replace PostgreSQL?**
No. Postgres is the ACID source of truth; ClickHouse is analytics-only.

**How is the password managed?**
OpenBAO → `clickhouse-credentials` `ClusterExternalSecret` in-cluster; an inline
dev password in local-stack.

---

## References

- [ClickHouse docs — MergeTree](https://clickhouse.com/docs/engines/table-engines/mergetree-family/mergetree)
- [Altinity clickhouse-operator](https://github.com/Altinity/clickhouse-operator)
- [OpenTelemetry Collector — ClickHouse exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/clickhouseexporter)
- [Grafana ClickHouse datasource](https://grafana.com/docs/plugins/grafana-clickhouse-datasource/latest/)
- [Grafana on ClickHouse — logs + traces deep dive](./grafana.md) (this area)
- Design: [RFC-0019](../../proposals/rfc/RFC-0019/) · [ADR-023](../../proposals/adr/ADR-023-clickhouse-observability-olap/)
- Observability hub: [`docs/observability/README.md`](../README.md)

---

_Last updated: 2026-07-19_
