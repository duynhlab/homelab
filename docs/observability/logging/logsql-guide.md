# LogsQL Guide — streams, filters, and pipes on this platform

How to query VictoriaLogs correctly here: which **stream** to address (the two
ingest paths create different stream fields — the #1 cause of "zero results"),
which **severity field** each path carries (the #2 cause), the filter syntax,
and the pipes that turn raw lines into answers. LogsQL runs in
**Grafana → Explore → VictoriaLogs** or directly against
`/select/logsql/query` on `:9428`. Every query in this guide was executed
against this cluster before being written down.

| | |
|---|---|
| **Datasource** | VictoriaLogs (`uid: victorialogs`), backend [`VLSingle :9428`](victorialogs.md) |
| **Golden rule** | Address logs by stream first (`_stream:{...}`), then filter fields |
| **Trap #1** | App services stream on `"service.name"`; Vector-shipped pods stream on `service` — not interchangeable |
| **Trap #2** | App records carry `severity_text` (OTLP model); only Vector-path records carry `level` |
| **Retention** | 7 days — for older data, SQL on ClickHouse [`otel_logs`](../clickhouse/README.md) (90d) |

---

## The mental model: streams, then fields

Every record has three special fields — `_time` (timestamp), `_msg` (the
message), `_stream` (its stream identity) — plus its regular fields. A query is
built in that order:

```logsql
_stream:{namespace="product"}   level:error   _time:15m
└─ which streams to read        └─ field filter └─ how far back
```

Filters on the same line are implicitly `AND`ed. The `_stream` filter is the
cheap one — it skips whole streams without reading them — so lead with it
whenever you know the workload. High-cardinality values (`trace_id`,
`query_id`) are deliberately **not** stream fields ([why](victorialogs.md#the-streams-model));
they are regular fields you filter directly: `trace_id:abc123`.

## Know your streams

The two ingest paths declare different stream fields, so **the same service
concept is addressed differently depending on who shipped the log** — and the
record's *shape* differs too:

| You want logs from… | Path | Query by | Severity field |
|---|---|---|---|
| A Go service (`product`, `cart`, `checkout`, …) or worker (`order-worker`, `checkout-worker`) | OTLP (otelzap → Collector) | `_stream:{"service.name"="checkout"}` | `severity_text` (`error`, `warn`, …) |
| The Envoy edge | OTLP (ADR-060) | `_stream:{"service.name"="platform.envoy-gateway"}` | none — access logs carry `status` instead (`severity_text` reads `Unspecified`) |
| A database, the frontend, a system pod | Vector | `_stream:{namespace="product"}` or `_stream:{service="frontend"}` (`service` = the pod's `app` label) | `level` (lifted from the JSON message when present) |
| PostgreSQL `auto_explain` plans | Vector (PG pipeline) | `_stream:{cluster_name="product-db"}` — fields: `cluster_name`, `namespace`, `database`, `query_id` | none — these are plans, not messages |

The names in `"service.name"` are the pods' `OTEL_SERVICE_NAME` — the bare
service name (`product`, not `product-service`). A dotted field name must be
quoted inside the stream filter.

**App records follow the OTel LogRecord model**
([`../../api/logs.md § OTel log data model`](../../api/logs.md#otel-log-data-model)):
the zap message becomes `_msg`, the zap level becomes `severity_text` /
`severity_number`, and every structured field becomes an attribute — alongside
resource attributes like `k8s.pod.name`, `service.instance.id`,
`code.function.name`. There is **no `level` field on this path**;
`level:error` silently matches nothing.

## Filters

### Time — `_time`

```logsql
_time:5m                                # last 5 minutes
_time:1h                                # last hour
_time:[2026-08-24, 2026-08-25)          # absolute range (half-open)
_time:5m error                          # combined: implicit AND
```

### Words, phrases, prefixes (against `_msg`)

```logsql
error                                   # word filter (tokenized — the safe default)
"connection refused"                    # phrase filter
err*                                    # prefix filter
*ampl*                                  # substring — case-sensitive!
_msg:i(error)                           # case-insensitive word
_msg:~"connection.*refused"             # regex (RE2) — the heaviest filter, scope it
```

### Field filters

```logsql
level:error                             # word match in a field (Vector path)
severity_text:error                     # the same thing on the app path
level:in(error, warn)                   # value-set match
level:="error"                          # exact value
uri:="/api/v1/products"*                # exact prefix
trace_id:abc123def456                   # high-cardinality regular field — no _stream needed
trace_id:*                              # field is present and non-empty
duration_ms:>100                        # numeric range (also range(100, Inf), range[a, b])
status:429                              # numbers are matched as values too
```

### Boolean logic

```logsql
_stream:{namespace="product"} (level:error OR level:warn)
_stream:{namespace="product"} -level:info        # NOT via leading minus
_stream:{namespace=~"platform|product"}          # regex inside the stream filter
```

## Pipes

Pipes post-process the filtered records — the LogsQL analogue of SQL's
`GROUP BY` / `ORDER BY` / `LIMIT`:

| Pipe | What it does | Example |
|---|---|---|
| `stats by (f) …` | aggregate per group | `\| stats by (namespace) count() as n` |
| `sort by (f desc)` | order | `\| sort by (n desc)` |
| `limit N` | cap results | `\| limit 10` |
| `top N (f)` | shortcut: most frequent values | `\| top 5 (route_name)` |
| `first N by (f)` | first/latest records | `\| first 10 by (_time desc)` |
| `uniq by (f) with hits` | distinct values + counts | `\| uniq by (severity_text) with hits` |
| `fields a, b` | project columns | `\| fields _time, status, uri` |
| `unpack_json` | lift JSON in `_msg` to fields | `\| unpack_json \| filter logger:=pgaudit` |
| `extract "…<f>…"` | parse fields out of text | `\| extract "duration: <dur> ms"` |
| `math expr as f` | compute derived fields | `\| math duration / 1000 as duration_s` |
| `stream_context` | surrounding lines of a match | `\| stream_context before 10 after 100` |

Stats functions that matter here: `count()`, `count_uniq(f)`, `sum(f)`,
`avg(f)`, `min(f)` / `max(f)`, and `quantile(0.95, f)` — several in one pipe:

```logsql
_time:5m | stats
  quantile(0.5, duration) p50,
  quantile(0.95, duration) p95,
  max(duration) max_ms
```

> **Version note:** the cluster runs VictoriaLogs `v1.51.0`, which rejects
> *bare filter pipes* — write `| filter host:*foo*` with the explicit `filter`
> keyword, not `| host:*foo*`. local-stack's `v1.52.0` accepts both
> ([component inventory](../README.md#component-inventory)).

## Recipes

All runnable here — each was executed against this cluster on 2026-08-25.

### Cross-cutting

**Everything for one request** — from a span's `trace_id`, across services:

```logsql
trace_id:abc123def456
```

**How many app records carry trace correlation right now:**

```logsql
_stream:{"service.name"!=""} trace_id:* _time:6h | stats count() as with_trace
```

**Noisiest streams** (ingest volume — run this before blaming retention):

```logsql
_time:1h | top 5 (_stream)
```

**Context around a crash** — the lines before/after a match, per stream
(stacktraces, panics, OOM):

```logsql
_time:1h "Retention policy enforcement failed" | stream_context before 5 after 20
```

**Latest N errors, newest first:**

```logsql
_time:1h level:error | first 10 by (_time desc)
```

### App services (OTLP path — `severity_text`, not `level`)

**One service's errors:**

```logsql
_stream:{"service.name"="checkout"} severity_text:error _time:15m
```

**Error leaderboard across the fleet** (found `order-worker` leading on this
cluster):

```logsql
_stream:{"service.name"!=""} severity_text:error _time:6h
  | stats by ("service.name") count() as errors | sort by (errors desc)
```

**What severities a service actually emits** (most app records are
info-level; the edge's access-log records read `Unspecified`):

```logsql
_stream:{"service.name"!=""} _time:6h | uniq by (severity_text) with hits
```

**Volume per service** (who talks the most on the OTLP path):

```logsql
_time:6h | stats by ("service.name") count() as n | sort by (n desc) | limit 10
```

### Edge (Envoy access logs — attributes, no `_msg`)

Edge records carry attributes but **no `_msg`**
([hub § edge](README.md#edge-access-logs-two-sinks-one-road)) — free-text
returns nothing; always address the stream and its fields. Successful probe
traffic is CEL-filtered at the source, so don't look for healthy `/health` hits.

**Status distribution** (this cluster during a k6 run: 4890×200, 853×429):

```logsql
_stream:{"service.name"="platform.envoy-gateway"} _time:6h
  | stats by (status) count() as hits | sort by (hits desc)
```

**Who is being rate-limited** (429 by client IP):

```logsql
_stream:{"service.name"="platform.envoy-gateway"} status:429 _time:6h
  | stats by (client) count() as hits | sort by (hits desc)
```

**Edge latency percentiles** (`duration` is ms; long-lived streaming
connections dominate `max`):

```logsql
_stream:{"service.name"="platform.envoy-gateway"} _time:6h
  | stats quantile(0.5, duration) p50, quantile(0.95, duration) p95, max(duration) max_ms
```

**Hottest routes:**

```logsql
_stream:{"service.name"="platform.envoy-gateway"} _time:6h | top 5 (route_name)
```

**5xx by route** (route_name is the HTTPRoute's generated name):

```logsql
_stream:{"service.name"="platform.envoy-gateway"} status:>499 _time:1h
  | stats by (route_name) count() as hits | sort by (hits desc)
```

**Derived fields with `math`** — slowest requests, duration in seconds:

```logsql
_stream:{"service.name"="platform.envoy-gateway"} _time:1h
  | math duration / 1000 as duration_s
  | fields _time, uri, status, duration_s | sort by (duration_s desc) | limit 10
```

### Infra / Vector path (`level` works here)

**Errors and warnings by namespace:**

```logsql
_time:1h level:in(error, warn)
  | stats by (namespace) count() as n | sort by (n desc)
```

**One pod's stderr-ish lines:**

```logsql
_stream:{pod_name="platform-db-1"} level:error _time:1h
```

### PostgreSQL plans (from the [Vector PG pipeline](vector.md#postgresql-pipeline))

**Slow plans with the columns that matter:**

```logsql
_stream:{cluster_name="product-db"} duration_ms:>100 _time:1h
  | fields _time, database, query_id, duration_ms, query_text
```

**Every execution of one query** (`query_id` is a stream field — this is the
whole point of the stream design):

```logsql
_stream:{query_id="-5191732810777595558"}
```

**Plan-volume health check** (count, distinct queries, slowest, average):

```logsql
_stream:{cluster_name!=""} _time:24h
  | stats count() as plans, count_uniq(query_id) as uniq_queries,
          max(duration_ms) as slowest_ms, avg(duration_ms) as avg_ms
```

**The failure sink must be empty** — records here mean a
[format contract](vector.md#the-two-format-contracts) broke:

```logsql
_stream:{"kubernetes.container_name"="postgres"} _time:1h
```

### pgaudit (rides the infra stream as raw CNPG JSON)

pgaudit rows are **not** unpacked into fields by Vector — the whole CNPG JSON
envelope is the `_msg`, with `"logger":"pgaudit"` a key *inside* it. So
`logger:pgaudit` (a field filter) matches nothing; filter the text, then
`unpack_json` when you need the structure:

```logsql
# fast scan: word filter on the raw text
_stream:{namespace="platform"} "pgaudit" _time:1h

# structured: unpack, then filter and project the audit fields
_stream:{namespace="platform"} "pgaudit" _time:30m
  | unpack_json | filter logger:=pgaudit
  | fields _time, record.audit.command, record.audit.statement
```

(Verified live: the unpacked records carry `record.audit.command` = `DELETE` /
`INSERT` / DDL and the full statement text.)

### Direct API (no Grafana)

```bash
kubectl port-forward -n monitoring svc/vlsingle-victoria-logs 9428:9428
curl -G 'http://localhost:9428/select/logsql/query' \
  --data-urlencode 'query=_stream:{"service.name"="checkout"} severity_text:error _time:15m' \
  --data-urlencode 'limit=20'
```

## Gotchas

1. **Wrong stream field = silent zero results.** `_stream:{service="checkout"}`
   matches nothing — app services live under `"service.name"` (they are
   excluded from Vector, which is what populates `service`). The reverse holds
   for Vector-shipped pods.
2. **Wrong severity field = silent zero results.** App records (OTLP) carry
   `severity_text`; only Vector-path records carry `level`. Filtering
   `level:error` on an app stream returns nothing — and vice versa.
3. **Only stream fields belong inside `_stream:{...}`.** A regular field there
   (e.g. `_stream:{level="error"}`) matches nothing — filter it outside:
   `_stream:{...} level:error`.
4. **Edge logs have no `_msg`.** VictoriaLogs renders `missing _msg field`;
   query by stream + attributes, never free text.
5. **pgaudit's `logger` is inside the JSON text, not a field.** Use a word
   filter (`"pgaudit"`) or `unpack_json` — see the recipe above.
6. **Substring filters are case-sensitive** (`*Error*` ≠ `*error*`); word
   filters tokenize and are the safer default, and `i(...)` gives you
   case-insensitive matching when you need it.
7. **Empty panel ≠ broken pipeline.** Retention is 7d and quiet windows are
   real — widen the time range before debugging
   ([checklist](victorialogs.md#troubleshooting--logs-ingested-but-blank-in-grafana)).
8. **`log→trace` is not clickable.** Copy the `trace_id` from the log line into
   the trace store; only the trace→log direction is wired
   ([details](victorialogs.md#grafana-datasource--trace-correlation)).

## References

- [VictoriaLogs store](victorialogs.md) — streams model, ingest contracts
- [Vector pipeline](vector.md) — what populates the infra streams
- [Application logging](../../api/logs.md) — the OTel LogRecord model behind the app-path fields
- [Logging hub](README.md) · [PromQL guide](../metrics/promql-guide.md) — the metrics-side counterpart
- [LogsQL reference](https://docs.victoriametrics.com/victorialogs/logsql/) ·
  [LogsQL examples](https://docs.victoriametrics.com/victorialogs/logsql-examples/) ·
  [SQL → LogsQL mapping](https://docs.victoriametrics.com/victorialogs/sql-to-logsql/)

---

_Last updated: 2026-08-25 — expanded from the first cut: full pipe/stats table
(`top`, `first`, `unpack_json`, `extract`, `math`, `stream_context`,
`quantile`, `count_uniq`), recipes grouped per stream family, every query
re-executed against the live cluster. Two field-contract corrections landed
with the expansion: app-path records carry `severity_text`, not `level` (the
old app examples matched nothing), and pgaudit's `logger` is a key inside the
raw CNPG `_msg`, not a queryable field — the old `logger:pgaudit` example also
matched nothing; the working recipes use a word filter + `unpack_json`._
