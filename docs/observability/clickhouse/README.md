# ClickHouse — OTel logs+traces OLAP

Open-source columnar OLAP giving the platform **long-retention SQL over
OpenTelemetry logs and traces** — the cross-day analytics the 7-day,
LogsQL/TraceQL-only ops primaries can't, plus the `otel_logs`↔`otel_traces`
`trace_id` JOIN in one store (**RFC-0019 Phase B**).

| | |
|---|---|
| **Status** | **Deployed** — local-stack + cluster (RFC-0019 Phase B) |
| **Role** | **Supplementary** OLAP for logs+traces SQL. Runs **alongside** VictoriaLogs / VictoriaTraces (day-to-day ops primaries), which are **unchanged** |
| **Engine** | `clickhouse/clickhouse-server:26.7`, ReplicatedMergeTree, **1 shard × 3 replicas** on a 3-node ClickHouse Keeper quorum |
| **Operator** | Altinity `clickhouse-operator` `0.27.3` + a `ClickHouseInstallation` CR and a `ClickHouseKeeperInstallation` CR |
| **Ingest** | OTel Collector contrib `clickhouse` exporter — fan-out on the **traces + logs** pipelines (metrics stay on VictoriaMetrics — **never** here) |
| **Tables** | `otel.otel_logs`, `otel.otel_traces` (+ `otel_traces_trace_id_ts` MV), auto-created `ON CLUSTER` by the exporter (`create_schema` + `cluster_name` + `table_engine`) |
| **Retention** | **TTL 90 days** (`ttl_only_drop_parts`) vs 7d on the ops primaries — the long-retention payoff |
| **Storage** | local PVC `standard` `10Gi` **per replica** (cluster) + small keeper PVCs; a named `clickhouse-data` volume (local-stack, which stays single-node) |
| **Query** | Grafana `grafana-clickhouse-datasource` **4.20.0** (`uid: clickhouse`, native `:9000`) + 5 provisioned dashboards in the **ClickHouse** folder (suite Overview→Logs→Traces, service deep dive, platform SQL) |
| **App code** | **Unchanged** — `pkg/obsx` / `pkg/grpcx` untouched; adding ClickHouse is a Collector-exporter change |
| **Design** | [RFC-0019](../../proposals/rfc/RFC-0019/) · [ADR-023](../../proposals/adr/ADR-023-clickhouse-observability-olap/) · [RFC-0028](../../proposals/rfc/RFC-0028/) · [ADR-065](../../proposals/adr/ADR-065-clickhouse-replicated-topology/) |

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
9. [Grafana](#grafana) — datasource, Explore, dashboard grammar, the standard suite
10. [Metrics & alerting](#metrics--alerting) — engine-health scrape, alert catalog, runbook stubs
11. [Playground — MergeTree by hand](#playground--mergetree-by-hand)
12. [Glossary](#glossary)
13. [ClickHouse vs PostgreSQL](#clickhouse-vs-postgresql)
14. [Commerce analytics (Phase A — not deployed)](#commerce-analytics-phase-a--not-deployed)
15. [FAQ](#faq)
16. [References](#references)

---

## Overview

VictoriaLogs and VictoriaTraces both cap at **7-day** retention and answer
**LogsQL / the Jaeger query API only**. There is no cross-day **SQL/OLAP** over
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
5th trace sink and the 2nd log sink; a failure there cannot stall the ops
primaries (`sending_queue` + `retry_on_failure` isolate it).

```mermaid
flowchart LR
  Apps["10 services + 2 workers<br/>+ edge"] -->|OTLP| Col["OTel Collector<br/>(contrib)"]
  Col -->|metrics| VM[("VictoriaMetrics")]
  Col -->|logs| VL[("VictoriaLogs")]
  Col -->|traces| VT[("VictoriaTraces")]
  Col -->|"logs + traces (RFC-0019)"| CH[("ClickHouse<br/>otel_logs / otel_traces")]
  CH --> Graf["Grafana<br/>clickhouse datasource"]

  classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
  classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
  classDef collector fill:#a5d8ff,color:#111,stroke:#1971c2;
  class Apps service;
  class Col collector;
  class VM,VL,VT,CH data;
```

**Logs-first analytics.** Traces are head-sampled (10% prod / 100% local), so
`otel_traces` counts undercount real traffic; `otel_logs` is **100% unsampled**
and is the counting workhorse. Traces are exemplars joined back on `trace_id`.

---

## How it works in this platform

| Aspect | Detail |
|--------|--------|
| **Engine** | `clickhouse/clickhouse-server:26.7`, ReplicatedMergeTree, 1 shard × 3 replicas ([ADR-065](../../proposals/adr/ADR-065-clickhouse-replicated-topology/)) |
| **Operator** | Altinity `altinity-clickhouse-operator` `0.27.3` (HelmRelease in the `controllers` wave, ns `monitoring`); CRDs health-checked before the CHI applies (`kubernetes/infra/controllers/clickhouse-operator/`) |
| **Instance** | `ClickHouseInstallation` `clickhouse` (cluster `otel`) → StatefulSets `chi-clickhouse-otel-0-{0,1,2}`, one per node (host anti-affinity); own Flux Kustomization `clickhouse-local` `dependsOn [controllers-local, secrets-local]`, health-checking **all three** (`kubernetes/infra/configs/clickhouse/`) |
| **Coordination** | `ClickHouseKeeperInstallation` `keeper`, 3 replicas, referenced by name (`zookeeper.keeper.name`); holds the replication metadata. A replica that loses its Keeper session serves reads and refuses writes |
| **Storage** | PVC `standard` `10Gi` per replica (`volumeClaimTemplates`) + keeper data `2Gi` / log `1Gi`; local-stack uses a named `clickhouse-data` volume |
| **Credentials** | `default` user password from OpenBAO `secret/local/infra/clickhouse/admin` via the `clickhouse-credentials` `ClusterExternalSecret` → Secret in `monitoring` (selector label `platform.duynhlab/clickhouse`); local-stack uses an inline dev password |
| **Ingest** | Collector contrib `clickhouse` exporter appended to the `traces` + `logs` pipelines; `create_schema: true` + `cluster_name: otel` + `table_engine: ReplicatedMergeTree` bootstraps the replicated tables `ON CLUSTER` (argument-free engine → server-default `{uuid}` replica path); `ttl: 2160h` (90d); `async_insert`, `sending_queue`, `retry_on_failure`; password via `${env:CLICKHOUSE_PASSWORD}` (`extraEnvs` secretKeyRef) |
| **Security** | `runAsNonRoot`, `runAsUser: 101`, `fsGroup: 101`, `allowPrivilegeEscalation: false`, drop `ALL` caps, `seccompProfile: RuntimeDefault`; `/ping` liveness+readiness; pinned image (PSS-baseline + no-latest) |
| **Access** | Grafana datasource `uid: clickhouse` (`clickhouse-clickhouse.monitoring.svc.cluster.local:9000`, native, password via `valuesFrom`); **not** on any public Ingress; the `default` password is the access control (no NetworkPolicy — `monitoring` has no default-deny and netpol is inert on kindnet; a `:9000`/`:8123` NetworkPolicy is a follow-up for an enforcing CNI) |
| **Startup ordering** | The collector's clickhouse exporter runs `CREATE DATABASE/TABLE` in `start()` (`create_schema`), so an unreachable ClickHouse fails the **whole** collector at startup. Ordered ClickHouse-first: local-stack via `depends_on: service_healthy`, cluster via `tracing-local dependsOn clickhouse-local`. `sending_queue`/`retry` isolate only *runtime* backpressure |
| **Dashboards** | 5 provisioned boards in the **ClickHouse** Grafana folder — see [Grafana](#grafana); local-stack via file provider, cluster via `configMapGenerator` → `GrafanaDashboard` CRs |
| **local-stack** | `clickhouse` compose service (`:8123` HTTP, `:9000` native), collector `clickhouse` exporter, Grafana plugin + provisioned datasource; e2e audit check **C6** (`SELECT count() FROM otel.otel_traces/otel_logs`) |

The Collector's other sinks are untouched: VictoriaLogs and VictoriaTraces
keep receiving, and the metrics pipeline never routes to ClickHouse.

---

## Operations

### Deployed schema (real DDL)

The contrib exporter created this `ON CLUSTER otel` — note the replicated
engine, the sort key, day-partitioning, 90-day TTL, per-column codecs, and
skipping indexes:

```sql
CREATE TABLE otel.otel_traces ON CLUSTER otel
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
ENGINE = ReplicatedMergeTree
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
- **`ENGINE = ReplicatedMergeTree`** with no arguments — the server's
  `default_replica_path` (`/clickhouse/tables/{uuid}/{shard}`) and
  `default_replica_name` (`{replica}`) apply, so every `CREATE` mints a fresh
  Keeper znode and a drop-and-recreate can never collide with a stale replica
  path. The exporter cannot pass engine arguments, which is part of why this
  style was chosen ([ADR-065](../../proposals/adr/ADR-065-clickhouse-replicated-topology/)).

### Retention & compression

| Table | Retention | Measured compression (local-stack) |
|-------|-----------|-----------------------------------|
| `otel_traces` | 90d | **10.5×** (1.20 MiB → 117 KiB) |
| `otel_logs` | 90d | **8×** (2.06 MiB → 262 KiB) |

Retention is **90 days** here vs **7 days** on VictoriaLogs/VictoriaTraces — the reason
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

All five provisioned dashboards are documented in [Grafana](#grafana) below —
the standard suite (Overview → Logs → Traces), the service deep dive, and the
platform-wide *OTel logs+traces SQL* board.

### Runbook — data not appearing

1. **Drive traffic**, then wait **~30–45s** (OTLP export + batch lag).
2. Collector export errors: `otelcol_exporter_send_failed_*` for the `clickhouse`
   exporter, or `kubectl logs -n monitoring deploy/otel-collector | grep -i clickhouse`.
3. ClickHouse reachable? `SELECT 1` (see [Playground](#playground--mergetree-by-hand)).
4. Tables exist? `SHOW TABLES FROM otel` — the exporter creates them on first write
   (`create_schema: true`); a wrong password blocks `CREATE DATABASE`.
5. VictoriaLogs/VictoriaTraces still receiving? They are independent sinks — ClickHouse being
   down must not affect them (`sending_queue` isolates backpressure).

---

## Grafana

Grafana turns the `otel` tables into an explorable logs/traces UI and a SQL
dashboard surface. Two ideas carry everything below:

1. **The plugin maps columns, it does not ingest** — Grafana only ever runs
   `SELECT`s; the OTel mapping tells it which columns mean *time*, *severity*,
   *body*, *trace id*, *duration*.
2. **The table's `ORDER BY` decides what is cheap** — service-first filters fly;
   bare trace-id lookups ride the `bloom_filter` index + the
   `otel_traces_trace_id_ts` MV (see [Deployed schema](#deployed-schema-real-ddl)).

### The datasource, as deployed

Plugin `grafana-clickhouse-datasource` **4.20.0** (pinned in the cluster
`GF_INSTALL_PLUGINS` and the local-stack compose). Both environments provision
the same shape (cluster: [`datasource-clickhouse.yaml`](../../../kubernetes/infra/configs/observability/grafana/datasource-clickhouse.yaml),
password from the ESO-managed `clickhouse-credentials` Secret; local-stack:
[`clickhouse.yaml`](../../../local-stack/observability/grafana/provisioning/datasources/clickhouse.yaml)):

```yaml
jsonData:
  host: clickhouse-clickhouse.monitoring.svc.cluster.local   # local: clickhouse
  port: 9000
  protocol: native
  defaultDatabase: otel
  username: default
  logs:    { defaultDatabase: otel, defaultTable: otel_logs,   otelEnabled: true }
  traces:  { defaultDatabase: otel, defaultTable: otel_traces, otelEnabled: true }
```

`otelEnabled: true` unlocks the Logs/Traces query builders, the Explore views,
and trace↔log navigation — without it the datasource is a plain SQL connection.

### OTel schema versions

The collector's exporter owns the DDL, and its shape changed at contrib
**0.151.0** (the `TimestampTime` helper column left `otel_logs`):

| Schema | Exporter | `otel_logs` shape |
|--------|----------|-------------------|
| 1.2.9 | contrib < 0.151.0 | has `TimestampTime` |
| **1.3.0** | contrib ≥ 0.151.0 | no `TimestampTime` — what both environments write (contrib `0.159.0`) |

Plugin ≥ 4.20.0 **auto-detects the logs schema from the table's columns** when
the version selector is on auto (latest); our provisioning deliberately does not
pin a version. After any collector bump, `DESCRIBE otel.otel_logs` tells you
which shape a table has — `create_schema` is create-if-absent, so an old table
keeps its old shape until dropped.

### Explore & trace↔log linking

- **Logs** query type generates the column mapping (`Timestamp AS timestamp,
  Body AS body, SeverityText AS level … ORDER BY Timestamp DESC LIMIT 1000`);
  our tables use the default OTel column names, so no custom mapping is needed.
  Builder filters become `WHERE` clauses — `ServiceName` is the cheap one
  (first `ORDER BY` key).
- **Traces** query type maps `TraceId`/`ServiceName`/`SpanName`/`Timestamp`/
  `Duration`; the waterfall detail view resolves a trace id to its time range
  via `otel_traces_trace_id_ts`, sidestepping the service-first sort key.
  `Duration` is nanoseconds — raw SQL panels divide by `1e6` for ms.
- **Linking**, both directions, rides the shared `TraceId` column: log line →
  "View trace"; span → logs filtered `WHERE TraceId = '<id>'`. One store, one
  key — no derived-fields bridge, which is exactly what the VictoriaLogs↔VictoriaTraces
  pair lacks (see [logging](../logging/README.md)).

### Dashboard grammar (raw SQL panels)

Time series: return a datetime aliased `time` plus numerics. Multi-line: field
order matters — time, then the string group, then the value:

```sql
SELECT $__timeInterval(Timestamp) AS time, ServiceName, count() AS spans
FROM otel.otel_traces
WHERE $__timeFilter(Timestamp)
GROUP BY time, ServiceName ORDER BY time
```

| Macro | Expands to |
|-------|------------|
| `$__timeFilter(col)` | `col >= <from> AND col <= <to>` — dashboard time picker |
| `$__timeInterval(col)` | `toStartOfInterval(col, INTERVAL <auto> second)` — adaptive bucketing |
| `$__fromTime` / `$__toTime` | picker edges as `DateTime` scalars — for subqueries/denominators |
| `$__conditionalAll(expr, $var)` | `expr` when the variable has a selection, `1=1` on *All* or an empty textbox |

Recipes live in the shipped dashboards — copy from there instead of reinventing:
error-rate % (`countIf(StatusCode = 'Error') / count()`), latency quantiles
(`quantile(0.95)(Duration)/1e6`), the trace↔log correlation JOIN.

### The standard dashboard suite — Overview → Logs → Traces

Three dashboards, one navigation story — each answers exactly one question:

| Tier | Dashboard (uid) | Question it answers |
|------|-----------------|---------------------|
| 1 | **OTel — Overview** (`clickhouse-otel-overview`) | *Which service is in trouble?* — the triage landing page |
| 2 | **OTel — Logs Explorer** (`clickhouse-logs-explorer`) | *What errors are happening?* |
| 3 | **OTel — Trace Explorer** (`clickhouse-traces-explorer`) | *Where did the request go and which span broke?* |

Overview's "who is in trouble" tables link a service into the Logs Explorer or
the [service deep dive](#the-service-deep-dive-dashboard); every `TraceId` cell
in the suite links into the Trace Explorer, which loads an **in-dashboard trace
waterfall** (`format: 3`, Jaeger-style aliases, window via the MV) with a
**"Logs for this trace"** panel underneath — logs↔traces on one screen.

Design decisions, all verified against live data:

- **Trace-level semantics**: per-trace panels group by `TraceId`; a trace is
  *failed* if ANY span has `StatusCode = 'Error'`; the root span is
  `ParentSpanId = ''` (exactly one per trace). The *Trace status* filter applies
  to that classification — never to member spans — and the volume-row stats
  ignore it by design (they ARE the status summary).
- **Native panels**: logs panels are `format: 2` (SQL aliases
  `timestamp`/`body`/`level`); the waterfall is `format: 3`; multi-line
  timeseries are `format: 0`. Only `format` is load-bearing.
- **Variables**: `$severity` is lowercase (`error,warn,info,notice,debug` — what
  the services actually emit); `$environment` reads
  `deployment.environment.name` (`local` locally, `production` in-cluster) and
  binds to member spans (the edge's own spans carry `deployment.environment.name: local`
  locally via a `customTags` literal, but the cluster CR tags pod identity
  instead and has no `deployment.environment.name`); textbox vars run through
  `$__conditionalAll`.
- **Duration heatmap**: raw `(time, duration_ms)` rows, panel-side bucketing,
  log₂ y-scale, `$sample_mod` constant (1 = no sampling; raise ~500 at volume).
  Span `Events.*` are not populated here — error text comes from `StatusMessage`.

### The service deep-dive dashboard

*ClickHouse — Service deep dive* (`clickhouse-service-deepdive`) applies the
same machinery to **one service at a time**; the platform-wide view stays in
*ClickHouse — OTel logs+traces SQL* (`clickhouse-otel-sql`). Seven rows:

| Row | Panels |
|-----|--------|
| Overview | req/s, error %, p95 (server spans), error-log count, distinct operations |
| Traffic & latency | rate by operation, p50/p95/p99, error % trend, log volume by severity |
| HTTP endpoints | route × method table (calls, 5xx, p95) + status classes — attributes `http.request.method` / `http.route` / `http.response.status_code` |
| gRPC methods | `rpc.method` split into Service/Method (calls, errors, p95) |
| Dependencies | who calls the service (client spans matching `<service>.v1.%`) · what it calls (gRPC callees + `postgresql`/`redis` client spans) |
| Slow & failing | slowest + error spans, TraceId → Explore data links |
| Logs | severity-filtered logs, top error messages, error-traces↔logs JOIN |

Two verified facts every new panel must respect: enum spellings are the short
ones (`StatusCode` `Ok`/`Error`/`Unset`, `SpanKind` `Server`/`Client`/`Internal`
— and Go-SDK success spans are `Unset`, so error-rate is `countIf(Error)/count()`),
and proto packages are named after the owning service, so "who calls product" is
just client spans where `rpc.method LIKE 'product.v1.%'`.

### Plugin-bundled dashboards (manual import — not GitOps)

The datasource ships 7 reference dashboards (datasource config page →
**Dashboards** tab). A UI import lives **only in that Grafana's database** — not
in git, never on the cluster, wiped when the local volume is recreated:

| Dashboard (uid) | Group | What it is |
|---|---|---|
| ClickHouse - Query Analysis (`w5Q2Otank`) | **Server admin** | Query performance over `system.query_log` |
| ClickHouse - Data Analysis (`-B3tt7a7z`) | Server admin | Table/parts/disk usage, compression |
| ClickHouse - Cluster Analysis (`_hAsuzBnz`) | Server admin | Replication/distributed health (mostly N/A single-node) |
| Advanced ClickHouse Monitoring (`e336c8cd-…`) | Server admin | Memory, merges, mark cache, background pools |
| OpenTelemetry Logs Explorer (`otel-logs-explorer`) | **OTel reference** | Upstream generic version of our Logs Explorer |
| OpenTelemetry Traces Explorer (`otel-traces-explorer`) | OTel reference | Upstream Trace Explorer — its heatmap hard-codes `% 500` sampling (near-empty at our volume) |
| OpenTelemetry Service Dashboard (`otel-service-dashboard`) | OTel reference | Upstream per-service view — the deep dive covers this with verified enums/keys |

The server-admin group watches ClickHouse *itself* (`system.*`) — a niche the
in-repo suite doesn't cover; promote one to a provisioned JSON + CR if it earns
a permanent place. Provisioned ClickHouse dashboards live in the **ClickHouse**
Grafana folder on both environments (local: file provider
`foldersFromFilesStructure` + `dashboards/ClickHouse/`; cluster: the CR
`folder:` field).

### Query performance rules

1. **Filter `ServiceName` first** — first `ORDER BY` key; granule pruning does
   the work (proven in the [Playground](#playground--mergetree-by-hand)).
2. **Always `$__timeFilter`** — day partitions make the picker a partition prune.
3. **`ORDER BY Timestamp DESC LIMIT n`** on log queries — never unbounded.
4. **Bare `TraceId` lookups** are for Explore/the trace panel, not per-refresh
   dashboard panels.
5. **Don't `SELECT *`** — name the `Map` keys you need
   (`ResourceAttributes['k8s.pod.name']`).

Integration checks: plugin version via `GET /api/plugins/grafana-clickhouse-datasource`
(→ `4.20.0`); datasource health via *Save & test* or `SELECT 1` in Explore; data
not appearing → [Runbook](#runbook--data-not-appearing).

---

## Metrics & alerting

> **Planned** — the manifests below are merged; the first scrape, the alert
> load into VMAlert, and the expression tuning all happen at the Kind gate.
> local-stack does not run the operator, so nothing here is exercisable on
> compose.

The five dashboards above watch the **data** (OTel rows over the SQL
datasource). This chapter is the **engine**: is the server up, is the disk
filling, are merges keeping pace with inserts. Before this landed the engine
view was blind — no scrape, no alert — and a dead ClickHouse surfaces in the
worst possible way: the OTel Collector's `create_schema` startup step blocks
every collector restart until the store returns.

### Metric sources

| Endpoint | Producer | Families | Use |
|---|---|---|---|
| operator Service `:8888/metrics` | Altinity operator | `clickhouse_operator_chi_reconciles_*`, `clickhouse_operator_host_reconciles_*`, pod events | Control-plane health |
| operator Service `:8888/chi` | metrics-exporter sidecar | `chi_clickhouse_metric_*` (system.metrics), `chi_clickhouse_event_*` (system.events), `chi_clickhouse_async_metric_*`, disks, parts, `chi_clickhouse_system_errors_*` | Engine health per CHI |
| CHI pod `:9363/metrics` (`settings.prometheus/*`) | `clickhouse-server` itself | `ClickHouseMetrics_*`, `ClickHouseProfileEvents_*`, `ClickHouseAsyncMetrics_*`, `ClickHouseErrorMetric_*` | Per-replica granularity |

Both operator endpoints are scraped by the **chart's ServiceMonitor**
(`serviceMonitor.enabled` in `controllers/clickhouse-operator/helmrelease.yaml`).

**The third source was enabled with replication** ([RFC-0028](../../proposals/rfc/RFC-0028/)),
and the reason is worth keeping: at 1×1 the exporter's `/chi` carried every
engine signal the alerts needed and a per-pod scrape would only have duplicated
it. Three replicas change the question the metrics have to answer. The exporter
aggregates by CHI, so it cannot say *which* replica is sick, and
`ClickHouseMetrics_ReadonlyReplica` — a replica that lost its Keeper session and
silently stopped accepting writes while still serving reads — has no equivalent
in the exporter's view at all. It is scraped per pod by
`podmonitors/clickhouse-server.yaml` (`job="clickhouse-server"`, label
`replica`); a PodMonitor rather than a ServiceMonitor because the
operator-generated Services carry only the native, HTTP and interserver ports.

### Alerts

Rules live in
`configs/observability/metrics/prometheusrules/observability/clickhouse-alerts.yaml`,
catalogued in [alert-catalog § 8b](../alerting/alert-catalog.md#8b-clickhouse-otel-olap-engine).
Three of the twelve this section once claimed were deleted on 2026-08-22 for
naming series the exporter does not publish — count the file, not the prose.

The spine: the **reachability pair** — `ClickHouseReplicaUnreachable` (warning:
one of three cannot be fetched, its peers still serve) escalating to
`ClickHouseAllReplicasUnreachable` (critical: the store is down and the
collector's `create_schema` will block every restart); the **replication pair**
— `ClickHouseZooKeeperExceptions` and `ClickHouseReadonlyReplica`, which catch
the failure nothing else notices, because a replica that lost its quorum keeps
answering reads while falling behind; the **disk pair** (<15% warn, <5%
critical, now counting data stored three times); the **insert-pressure ladder**
(delayed → too-many-parts); and the consumer-side **ExporterUnhealthy** (the
collector's `send_failed_*{exporter="clickhouse"}` — the collector can be up
while its ClickHouse exporter backpressures).

### Dashboard

`ClickHouse Server / Engine` (folder ClickHouse, VictoriaMetrics datasource —
not the SQL one): up/uptime, query and insert rates, the insert-pressure
ladder, parts and merges, disk and memory, a `system.errors` top-N table, and
the operator's reconcile counters.

### Runbook stubs

- **ClickHouseServerUnreachable** — `kubectl -n monitoring get po -l
  clickhouse.altinity.com/chi=clickhouse`, then pod logs. If the pod is up but
  fetch fails, check the `clickhouse-credentials` Secret sync (ESO). Remember
  the blast radius: collector restarts block on `create_schema` until the
  store returns — do not bounce collectors while this fires.
- **ClickHouseDiskCritical** — `SELECT sum(bytes_on_disk) FROM system.parts
  GROUP BY table` to find the eater; drop the oldest partitions
  (`ALTER TABLE … DROP PARTITION …`) or grow the PVC. The 30-day TTL cannot
  rescue a same-day spike.
- **ClickHouseTooManyParts** — inserts too small or merges starved. Check the
  collector's batch processor settings first (bigger, fewer inserts), then
  merge failures on the dashboard.
- **ClickHouseExporterUnhealthy** — engine-side cause fires alongside it if
  CH is the problem; alone, it points at the collector's exporter config or
  the network path. VictoriaLogs/VictoriaTraces hold their own copies, so
  loss is scoped to the OLAP store.

---

## Playground — MergeTree by hand

Explore the **live** engine. All output below is from the running local-stack
instance — reproduce it to see MergeTree's write→part→merge→TTL lifecycle.

### Connect

```bash
# local-stack — HTTP (:8123) or interactive client (:9000)
curl -s 'http://localhost:8123/' -u default:otel --data-binary 'SELECT version()'
docker compose exec clickhouse clickhouse-client --password otel

# cluster — exec into one of the three operator-managed pods.
# Pod name is chi-<chi>-<cluster>-<shard>-<replica>-<ordinal>, so the replicas
# are ...-0-0-0, ...-0-1-0 and ...-0-2-0. Which one you land on matters for any
# system.* question: system.parts, system.replicas and system.replication_queue
# are per-replica views, and the round-robin Service will not tell you who
# answered. Loop over the pods when comparing them.
PW=$(kubectl get secret -n monitoring clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -it -n monitoring chi-clickhouse-otel-0-0-0 -- clickhouse-client --password "$PW"

# all three, e.g. to confirm a table really has three live replicas
for p in $(kubectl -n monitoring get po -l clickhouse.altinity.com/chi=clickhouse -o name); do
  echo "== $p"
  kubectl -n monitoring exec "${p#pod/}" -- clickhouse-client --password "$PW" -q \
    "SELECT table, is_readonly, total_replicas, active_replicas, absolute_delay
     FROM system.replicas WHERE database='otel' FORMAT PrettyCompact"
done
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
SELECT count() FROM otel.otel_traces WHERE ServiceName = 'platform.envoy-gateway-system';
```
```
ReadFromMergeTree (otel.otel_traces)
Indexes:
  PrimaryKey
    Keys:  ServiceName
    Condition: (ServiceName in ['platform.envoy-gateway-system', 'platform.envoy-gateway-system'])
    Parts: 1/5          -- 4 parts skipped outright
    Granules: 1/5       -- only 1 granule read
```
Because `ServiceName` is the first `ORDER BY` key, ClickHouse reads **1 of 5
granules** instead of scanning everything — the payoff of the sort key.
`platform.envoy-gateway-system` is the edge's `service.name` as **derived** by
Envoy Gateway (`<gateway>.<namespace>`, locally `platform` in
`envoy-gateway-system`) — not configured, and environment-dependent since it
embeds the namespace.

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
| Live ops log/trace triage | VictoriaLogs / VictoriaTraces |
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

**Does this replace VictoriaLogs / VictoriaTraces?**
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
- [Grafana ClickHouse datasource](https://grafana.com/docs/plugins/grafana-clickhouse-datasource/latest/) · [ClickHouse docs — Using Grafana](https://clickhouse.com/docs/observability/grafana)
- [Grafana ClickHouse datasource](https://grafana.com/docs/plugins/grafana-clickhouse-datasource/latest/)
- Design: [RFC-0019](../../proposals/rfc/RFC-0019/) · [ADR-023](../../proposals/adr/ADR-023-clickhouse-observability-olap/)
- Observability hub: [`docs/observability/README.md`](../README.md)

---

_Last updated: 2026-08-28 — the store is replicated: 1 shard × 3 replicas on a ClickHouse Keeper quorum, `ReplicatedMergeTree` created `ON CLUSTER` by the exporter, and the engine-native `:9363` scrape finally enabled per replica ([RFC-0028](../../proposals/rfc/RFC-0028/) / [ADR-065](../../proposals/adr/ADR-065-clickhouse-replicated-topology/)). Two corrections found while writing it: the per-pod endpoint is `:9363`, not `:8001`, and the alert count in § Alerts had been stale since three rules were deleted in August. Earlier: trace-sink ordinal corrected from 4th to 5th (that note predated ADR-040's parallel run)._
