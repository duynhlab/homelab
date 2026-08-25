# VictoriaLogs — the log store

The **backend** of the logs pillar: a single-binary log database that both log
paths ([hub](README.md)) land in — Vector over jsonline, the OpenTelemetry
Collector over OTLP — queryable with LogsQL and correlated to traces by
`trace_id`. This doc owns the store: the streams model, the deployed `VLSingle`,
every ingest contract, retention, and the scale-out path. Collection is
[`vector.md`](vector.md); the query language is
[`logsql-guide.md`](logsql-guide.md).

| | |
|---|---|
| **Deployment** | `VLSingle` CRD (VM Operator), name `victoria-logs`, ns `monitoring` |
| **Service** | `vlsingle-victoria-logs.monitoring.svc` `:9428` |
| **Retention** | `7d`, 20Gi PVC (ClickHouse `otel_logs` is the 90-day second store) |
| **Ingest** | `/insert/jsonline` (Vector) · `/insert/opentelemetry/v1/logs` (Collector) |
| **Query** | LogsQL — `/select/logsql/query` + Grafana datasource `victorialogs` |
| **Manifest** | [`kubernetes/infra/configs/observability/logging/victorialogs/vlsingle.yaml`](../../../kubernetes/infra/configs/observability/logging/victorialogs/vlsingle.yaml) |

---

## The streams model

VictoriaLogs indexes logs by **stream**: the unique combination of a small set
of **stream fields**, declared per ingest request via the `VL-Stream-Fields`
header. A stream behaves like a Prometheus time series — cheap to seek, cheap
to filter — and everything else in the record is a **regular field**, stored
columnar and searchable without being indexed as an identity.

That split is the whole design contract:

- **Stream fields** must be **low-cardinality** and stable for a workload's
  lifetime: `namespace`, `service`, `pod_name`, `container_name` on the Vector
  path; `service.name` on the OTLP path. Filtering by stream
  (`_stream:{...}`) skips every non-matching stream without reading it.
- **High-cardinality values stay in the record body**: `trace_id`, `user_id`,
  `query_id`. They remain first-class queryable fields (`trace_id:abc123`), but
  they never multiply the stream index. This is exactly the failure mode that
  forces label discipline on Loki; VictoriaLogs makes the safe layout the
  natural one.

The rule to carry to any scale: **never promote a high-cardinality field to a
stream field.**

## VLSingle deployment

The store is the **operator-managed `VLSingle` CRD**, not a Helm chart — the VM
Operator (which also runs VMSingle/VMAgent, see
[`../metrics/victoriametrics.md`](../metrics/victoriametrics.md)) reconciles it
into a StatefulSet with a PVC.

```yaml
apiVersion: operator.victoriametrics.com/v1
kind: VLSingle
metadata:
  name: victoria-logs
  namespace: monitoring
spec:
  retentionPeriod: "7d"
  storage:
    resources:
      requests:
        storage: 20Gi
  resources:
    requests:
      cpu: 50m
      memory: 192Mi
    limits:
      cpu: 500m
      memory: 768Mi
```

Two settings carry history worth knowing:

- **No `removePvcAfterDelete`.** The field looks plausible (VMSingle has it) but
  `VLSingleSpec` v1 never defined it — the API server pruned it silently until
  the CRDs-catalog schema check in `flux-validate.sh` caught it, and it was
  removed from the manifest. Don't re-add it.
- **Memory limit is 768Mi, not the 128Mi it started at.** The fleet-wide CNPG
  postgres/pgaudit volume OOMKilled the store repeatedly (exit 137); every OOM
  restart dropped Vector's sink connection and lost in-flight records (sparse
  pgaudit rows first). The manifest comment records the bump.

## Ingestion endpoints

| Endpoint | Purpose | Used by |
|----------|---------|---------|
| `/insert/jsonline` | JSON Lines ingest | Vector sinks (infra path) |
| `/insert/opentelemetry/v1/logs` | OTLP logs ingest | OpenTelemetry Collector (app + edge path) |
| `/insert/elasticsearch` | Elasticsearch-compatible bulk API | available, unused here |
| `/select/logsql/query` | LogsQL query API | Grafana datasource, `curl` |

### Per-sender ingest contract

Each sender declares its own stream identity and message field in request
headers — **the headers differ per sink**, and getting them wrong silently
produces unqueryable streams:

| Sender / sink | `VL-Msg-Field` | `VL-Stream-Fields` |
|---|---|---|
| Collector `otlp_http/victorialogs` ([manifest](../../../kubernetes/infra/controllers/tracing/otel-collector/otel-collector.yaml)) | OTLP body | `service.name` |
| Vector `victorialogs_all` | `message` | `namespace,service,pod_name,container_name` |
| Vector `victorialogs_pg_plans` | `plan_json` | `cluster_name,namespace,database,query_id` |
| Vector `victorialogs_pg_parse_failures` | `message` | `kubernetes.container_name,kubernetes.pod_name` |

All three Vector sinks also send `VL-Time-Field: timestamp` and the default
multi-tenancy headers `AccountID: "0"` / `ProjectID: "0"`. Sink internals
(inputs, batching, buffers) are in [`vector.md`](vector.md#sinks).

## Stream catalog

What actually lands in the store, by stream identity:

| Stream | Fields | Content |
|---|---|---|
| **App services** | `service.name` = `product`, `cart`, `checkout`, … + workers `order-worker`, `checkout-worker` | zapx JSON via otelzap tee → Collector; `trace_id` a regular field |
| **Edge** | `service.name` = `platform.envoy-gateway` | Envoy access log via the Collector (ADR-060); attributes only, **no `_msg`** — see [hub § edge](README.md#edge-access-logs-two-sinks-one-road) |
| **Infra / everything else** | `namespace`, `service`, `pod_name`, `container_name` | Vector-tailed stdout: databases, frontend, system pods. `service` comes from the pod's `app` label (pod name as fallback) |
| **PG query plans** | `cluster_name`, `namespace`, `database`, `query_id` | Parsed `auto_explain` execution plans (`plan_json` as message); requires `auto_explain.log_format: "json"` on the CNPG cluster (set on platform-db/product-db) — see [`vector.md § PostgreSQL pipeline`](vector.md#postgresql-pipeline) |
| **PG parse failures** | `kubernetes.container_name`, `kubernetes.pod_name` | Records the plan parser dropped, for debugging the parser itself |

**pgaudit** records ride the infra stream, not a dedicated one: all CNPG
clusters enable `pgaudit` (`pgaudit.log = 'ddl, write'`), CNPG formats the rows
as JSON, and they land via `victorialogs_all` — the whole CNPG envelope is the
`_msg`, with `"logger":"pgaudit"` a key *inside* it (not a queryable field).
Verified live for `platform-db` and `product-db`. Query with a word filter,
`unpack_json` for structure:
`_stream:{namespace="platform"} "pgaudit" | unpack_json | filter logger:=pgaudit`
([recipe](logsql-guide.md#pgaudit-rides-the-infra-stream-as-raw-cnpg-json)).

## Grafana datasource & trace correlation

Provisioned by GitOps as plugin `victoriametrics-logs-datasource`:

- **CR**: [`kubernetes/infra/configs/observability/grafana/datasource-victorialogs.yaml`](../../../kubernetes/infra/configs/observability/grafana/datasource-victorialogs.yaml)
- **UID**: `victorialogs` · **URL**: `http://vlsingle-victoria-logs.monitoring.svc.cluster.local:9428`

Correlation is asymmetric today:

- **Trace → log works.** The VictoriaTraces datasource carries `tracesToLogsV2`
  (datasource `victorialogs`, tag `trace_id`), so a span's **Logs** tab shows
  the correlated lines. Configured on `datasource-victoriatraces.yaml`.
- **Log → trace is not wired.** The VictoriaLogs datasource has no
  `derivedFields`, so a `trace_id` in a log line is not a clickable link — copy
  it and search the trace store. A gap, not a feature; it predates
  [RFC-0027](../../proposals/rfc/RFC-0027/README.md).

## Retention & sizing

`7d` / 20Gi suits the homelab; VictoriaLogs compresses well, so size production
by *ingest-rate × retention*. The practical limit is **PVC fill** — and note the
guard's caveat: `KubePersistentVolumeFillingUp` exists (warning <15% free,
critical <5%) but is **inactive on Kind**, because the local-path CSI reports no
kubelet VolumeStats ([alert catalog](../alerting/alert-catalog.md)). On this
cluster the fill limit is effectively unwatched; on a real CSI it is covered.

## Scaling: VLSingle → VictoriaLogs cluster

**VLSingle is single-node** — no replication, no HA; homelab-grade as deployed.
When one node stops being enough, the upgrade path is the VictoriaLogs cluster
topology (`vlinsert` / `vlstorage` / `vlselect`) for horizontal scale-out and
replication — **same LogsQL, same ingest contract, no sender changes**: the two
ingest endpoints above simply move behind `vlinsert`.

## Verification

```bash
# CR + pod status
kubectl get vlsingle -n monitoring
kubectl get pods -n monitoring -l app.kubernetes.io/name=vlsingle

# Health + a direct LogsQL query
kubectl port-forward -n monitoring svc/vlsingle-victoria-logs 9428:9428
curl http://localhost:9428/health
curl -G 'http://localhost:9428/select/logsql/query' \
  --data-urlencode 'query=_stream:{namespace="product"}' --data-urlencode 'limit=10'

# PG plan stream has data
curl -G 'http://localhost:9428/select/logsql/query' \
  --data-urlencode 'query=_stream:{cluster_name!=""}' --data-urlencode 'limit=10'
```

## Troubleshooting — logs ingested but blank in Grafana

Logs answer on VictoriaLogs' own API but Explore / a panel is empty:

1. **Reachable from the Grafana pod?**
   ```bash
   kubectl exec -n monitoring deploy/grafana -- \
     wget -qO- --timeout=5 http://vlsingle-victoria-logs.monitoring.svc.cluster.local:9428/health
   ```
2. **Datasource healthy?** Plugin `victoriametrics-logs-datasource`, UID
   `victorialogs`, provisioned by `datasource-victorialogs.yaml` —
   Connections → Data sources → VictoriaLogs → Save & Test.
3. **Query shape.** Widen the time range (retention is 7d — an empty "Last 15
   minutes" is often a quiet window), and put **only stream fields** inside
   `_stream:{...}` — a non-stream field there matches nothing; use a field
   filter instead ([guide](logsql-guide.md#gotchas)).

Pipeline-side failures (nothing ingested at all, PG plans missing) are
[`vector.md § Troubleshooting`](vector.md#troubleshooting).

## References

- [Logging hub](README.md) — architecture, the two paths, why this stack
- [Vector pipeline](vector.md) · [LogsQL guide](logsql-guide.md)
- [Application logging (app contract)](../../api/logs.md) — the
  [OTel LogRecord data model](../../api/logs.md#otel-log-data-model) every exported record follows
- [ClickHouse `otel_logs`](../clickhouse/README.md) — the 90-day SQL second store
- [VictoriaLogs docs](https://docs.victoriametrics.com/victorialogs/) ·
  [data ingestion](https://docs.victoriametrics.com/victorialogs/data-ingestion/) ·
  [VLSingle operator resource](https://docs.victoriametrics.com/operator/resources/vlsingle/)

---

_Last updated: 2026-08-25 — split out of the logging README (hub keeps the
architecture; this doc owns the store). Corrected against the manifests: the
config snippet no longer shows `removePvcAfterDelete` (never valid on VLSingle
v1, removed from the manifest), and the PVC-fill alert's Kind caveat is stated._
