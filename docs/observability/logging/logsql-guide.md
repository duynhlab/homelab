# LogsQL Guide — streams, filters, and pipes on this platform

How to query VictoriaLogs correctly here: which **stream** to address (the two
ingest paths create different stream fields — the #1 cause of "zero results"),
the filter syntax, and the pipes that turn raw lines into answers. LogsQL runs
in **Grafana → Explore → VictoriaLogs** or directly against
`/select/logsql/query` on `:9428`.

| | |
|---|---|
| **Datasource** | VictoriaLogs (`uid: victorialogs`), backend [`VLSingle :9428`](victorialogs.md) |
| **Golden rule** | Address logs by stream first (`_stream:{...}`), then filter fields |
| **The trap** | App services stream on `"service.name"`; Vector-shipped pods stream on `service` — the fields are **not** interchangeable |
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
concept is addressed differently depending on who shipped the log**:

| You want logs from… | Path | Query by |
|---|---|---|
| A Go service (`product`, `cart`, `checkout`, …) or worker (`order-worker`, `checkout-worker`) | OTLP (otelzap → Collector) | `_stream:{"service.name"="checkout"}` |
| The Envoy edge | OTLP (ADR-060) | `_stream:{"service.name"="platform.envoy-gateway"}` |
| A database, the frontend, a system pod | Vector | `_stream:{namespace="product"}` or `_stream:{service="frontend"}` (`service` = the pod's `app` label) |
| PostgreSQL `auto_explain` plans | Vector (PG pipeline) | `_stream:{cluster_name="product-db"}` — fields: `cluster_name`, `namespace`, `database`, `query_id` |

The names in `"service.name"` are the pods' `OTEL_SERVICE_NAME` — the bare
service name (`product`, not `product-service`). A dotted field name must be
quoted inside the stream filter.

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
error                                   # word filter
"connection refused"                    # phrase filter
err*                                    # prefix filter
*ampl*                                  # substring — case-sensitive!
```

### Field filters

```logsql
level:error                             # word match in a field
level:="error"                          # exact value
uri:="/api/v1/products"*                # exact prefix
trace_id:abc123def456                   # high-cardinality regular field — no _stream needed
duration_ms:>100                        # numeric range (also range(100, Inf), range[a, b])
```

### Boolean logic

```logsql
_stream:{namespace="product"} (level:error OR level:warn)
_stream:{namespace="product"} -level:info        # NOT via leading minus
```

## Pipes

Pipes post-process the filtered records — the LogsQL analogue of SQL's
`GROUP BY` / `ORDER BY` / `LIMIT`:

```logsql
... | stats by (field) count() as n     # aggregate
... | sort by (n desc)                  # order
... | limit 10                          # cap
... | uniq by (host) with hits          # distinct values + counts
... | fields _time, level, message      # project columns
```

> **Version note:** the cluster runs VictoriaLogs `v1.51.0`, which rejects
> *bare filter pipes* — write `| filter host:*foo*` with the explicit `filter`
> keyword, not `| host:*foo*`. local-stack's `v1.52.0` accepts both
> ([component inventory](../README.md#component-inventory)).

## Recipes (all runnable here)

**Everything for one request** — from a span's `trace_id`, both app-path and
any trace-carrying lines, across services, in one query:

```logsql
trace_id:abc123def456
```

**A service's errors, last 15 minutes:**

```logsql
_stream:{"service.name"="checkout"} level:error _time:15m
```

**Error count per stream over the last hour** (who is failing loudest):

```logsql
_time:1h level:error | stats by (_stream) count() as errors | sort by (errors desc) | limit 10
```

**Noisiest streams** (ingest volume — run this before blaming retention):

```logsql
_time:5m | stats by (_stream) count() as logs | sort by (logs desc) | limit 10
```

**Edge: recent 5xx by route.** Edge records carry attributes but **no `_msg`**
([hub § edge](README.md#edge-access-logs-two-sinks-one-road)) — free-text
returns nothing; always address the stream and its fields:

```logsql
_stream:{"service.name"="platform.envoy-gateway"} status:>499 _time:1h
  | stats by (route_name) count() as hits | sort by (hits desc)
```

**Slow PostgreSQL plans** (from the [Vector PG pipeline](vector.md#postgresql-pipeline)):

```logsql
_stream:{cluster_name="product-db"} duration_ms:>100 _time:1h
  | fields _time, database, query_id, duration_ms, query_text
```

**pgaudit DDL/write trail** for a database cluster:

```logsql
_stream:{namespace="platform"} logger:pgaudit _time:24h
```

**Direct API** (no Grafana):

```bash
kubectl port-forward -n monitoring svc/vlsingle-victoria-logs 9428:9428
curl -G 'http://localhost:9428/select/logsql/query' \
  --data-urlencode 'query=_stream:{"service.name"="checkout"} level:error _time:15m' \
  --data-urlencode 'limit=20'
```

## Gotchas

1. **Wrong stream field = silent zero results.** `_stream:{service="checkout"}`
   matches nothing — app services live under `"service.name"` (they are
   excluded from Vector, which is what populates `service`). The reverse holds
   for Vector-shipped pods.
2. **Only stream fields belong inside `_stream:{...}`.** A regular field there
   (e.g. `_stream:{level="error"}`) matches nothing — filter it outside:
   `_stream:{...} level:error`.
3. **Edge logs have no `_msg`.** VictoriaLogs renders `missing _msg field`;
   query by stream + attributes, never free text.
4. **Substring filters are case-sensitive** (`*Error*` ≠ `*error*`); word
   filters tokenize and are the safer default.
5. **Empty panel ≠ broken pipeline.** Retention is 7d and quiet windows are
   real — widen the time range before debugging
   ([checklist](victorialogs.md#troubleshooting--logs-ingested-but-blank-in-grafana)).
6. **`log→trace` is not clickable.** Copy the `trace_id` from the log line into
   the trace store; only the trace→log direction is wired
   ([details](victorialogs.md#grafana-datasource--trace-correlation)).

## References

- [VictoriaLogs store](victorialogs.md) — streams model, ingest contracts
- [Vector pipeline](vector.md) — what populates the infra streams
- [Logging hub](README.md) · [PromQL guide](../metrics/promql-guide.md) — the metrics-side counterpart
- [LogsQL reference](https://docs.victoriametrics.com/victorialogs/logsql/) ·
  [LogsQL examples](https://docs.victoriametrics.com/victorialogs/logsql-examples/)

---

_Last updated: 2026-08-25 — first version, split out of the logging README.
Every example is addressed to a stream that exists on this platform (the old
README's `_stream:{service="auth"}` matched nothing: auth-service is retired
per RFC-0024, and app services stream on `"service.name"`, not `service`)._
