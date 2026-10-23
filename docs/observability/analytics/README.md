# Analytics telemetry and operations

Analytics must reveal stale commerce data even when nobody opens the portal.
Its sampler measures target-observed source freshness — on Kind the real CDC
heartbeat path (pg_cron in product-db → PeerDB → ClickHouse,
[docs/databases/cdc](../../databases/cdc/README.md)); in local-stack the
fixture's `analytics-heartbeat` container stands in for it. It does not replace the per-request freshness checks that authorize an API
response.

**Status: the signals are deployed; the alert rules and dashboard in this
directory are still candidates.** The sampler, its three gauges, the DB duration
histogram and the ClickHouse client spans ship with `analytics-service`
(`v0.1.0`) in local-stack (row C23) and on Kind (row K5.11, run
2026-10-23). `alerts.yaml` and `dashboard.json` are reviewable candidates,
deliberately not wired into Flux: promote them with the metric names
VictoriaMetrics stores (metric `analytics_source_state_ratio`, state label
`analytics_source_state`). The read-path finding (analytics-service#4) is
settled as an owner-accepted known limit, so promotion no longer waits on it.

| Fact | Contract |
|---|---|
| Owner | analytics-service; shared HTTP instrumentation remains in `pkg/httpmw` |
| Sources | `order`, `checkout`, `payment` |
| Sampling | Immediate startup read, then every 30 s; 2 s timeout; no overlapping reads |
| Snapshot | One immutable three-source batch; expires after 65 s |
| Collection | In-memory only; lag ages with the clock between samples |
| Shutdown | Join sampler and unregister callbacks before database and telemetry cleanup |
| API | [Analytics contract](../../api/analytics.md); response freshness stays per-request |
| Audit | [Source review and Linux qualification](audit.md) |

## Signals and their meaning

| OTel instrument | Type / unit | Dimensions | Meaning |
|---|---|---|---|
| `analytics.source.lag` | Observable gauge / `s` | `analytics.source.name` | Current age of the last valid target heartbeat; omitted on unknown |
| `analytics.source.state` | Observable gauge / `1` | Source name, `analytics.source.state` | Four 0/1 series per source; exactly one equals 1 |
| `analytics.freshness.last_success.time` | Observable gauge / `s` | None | Unix timestamp of last fully valid batch; absent until first success |
| `db.client.operation.duration` | Histogram / `s` | `db.system.name`, `db.namespace`, `db.operation.name`, `db.query.summary`, optional `error.type` | Query, scan and close duration; one observation per adapter operation |

Freshness state is `healthy` at age **≤120 s**, `stale` at **>120 and ≤300 s**,
and `unavailable` at **>300 s**. A stale heartbeat is still a valid observation;
it updates last-success time. `unknown` means missing, duplicate, zero, future,
unrecognized-source data, query failure, no initial sample, or snapshot expiry.
Any malformed batch invalidates all three source observations until the next
fully valid batch. Last-success time remains available after a later failure.
Do not interpret an absent lag series as zero or healthy.

The old request-driven `analytics.source.lag` histogram and
`analytics.source.observations` counter are removed before first deployment.
There is no dual publishing under one metric name. If a prototype has already
written the histogram, restrict the dashboard to the new release and retire its
old `_bucket`, `_sum`, and `_count` queries.

## Trace and log ownership

The shared middleware owns the HTTP server span, RED metrics and access record.
The business span `analytics.overview` carries a bounded
`analytics.unavailable.reason`: `freshness`, `query`, `timeout`, `limits`,
`validation`, or `cancelled`. A client span wraps each ClickHouse adapter query
and propagates its span context through clickhouse-go. The driver supports that
propagation; it does not replace this adapter's duration/span instrumentation.

Client spans and duration metrics share the same bounded `error.type` for
failed operations. Intentional caller cancellation leaves span status unset and
omits `error.type`; the overview span retains reason `cancelled`. Deadlines and
ClickHouse timeout exceptions are `timeout`, not caller cancellation. There is
no SQL text, parameter, customer identifier or raw driver error in these signals.

The canonical HTTP access log continues to record `error.type=503`. Follow its
trace ID to the operation span for the detailed reason; do not add a second
access/error log merely to repeat that reason. Sampling can omit the span, so a
trace-linked detailed reason is not guaranteed for every request. HTTP error
metrics and freshness state remain available independently of trace sampling.
Public API errors remain `ANALYTICS_UNAVAILABLE`.

## Identity and cardinality budget

Use `service.name=analytics` (the fleet short name from `OTEL_SERVICE_NAME`, as compose and the ResourceSet set it) and the shared resource builder. Set the
release version and a distinct pod identity on every replica. The current
vmagent promotion allowlist preserves `k8s.pod.name`, **not**
`service.instance.id`; the candidate dashboard therefore splits by
`k8s_pod_name` and `analytics_source_name`. In Compose, supply a distinct
`k8s.pod.name` resource value per simulated replica. Do not expand the platform's
promotion allowlist as a side effect of this service rollout.

- Freshness: 3 lag + 3 × 4 state + 1 last-success = **16 series per replica**.
- DB: 6 production summaries (`heartbeats`, `ready`, `daily`, `captured`,
  `products`, `funnel`) × 5 outcomes (no error, query, timeout, limits,
  validation) × 12 histogram series = **360 series per replica** maximum.
  Nine finite `obsx.DBDurationBuckets` plus `+Inf`, sum and count produce 12.
- Combined custom freshness + DB budget: **376 per replica**, 752 for two
  replicas, excluding shared HTTP/runtime metrics, target metadata and rollout
  overlap. A defensive `SELECT analytics` summary is reserved for unexpected
  internal call sites; any production occurrence is an audit failure, not an
  invitation to add arbitrary summaries.

No product/customer ID, filter date, SQL, error text or trace ID is a metric
label. Historical series from replaced versions/pods add churn; measure the
active head and the retention-window total separately.

## Dashboard and alert candidates

[dashboard.json](dashboard.json) is an importable Grafana dashboard, using a
Prometheus-compatible datasource variable. It shows individual source/pod lag,
one-hot state, time since sampler success, and query p95. **Never sum lag across
replicas**: summation makes two healthy replicas appear twice as stale.

[alerts.yaml](alerts.yaml) contains Prometheus-format rule candidates, not a
loaded `PrometheusRule`. The names are the ones VictoriaMetrics stores after
OTLP-to-Prometheus unit suffixing, verified on local-stack 2026-10-22:
`analytics_source_lag_seconds`, `analytics_source_state_ratio` (unit `1`
becomes `_ratio`), `analytics_freshness_last_success_time_seconds` and
`db_client_operation_duration_seconds`. The `service_name` label is
retained on both platform and Compose OTLP paths.

| Alert | Dwell | Meaning and first action | Recovery |
|---|---|---|---|
| AnalyticsSourceStale | 1 min | Age >120 and ≤300 s; inspect source heartbeat and mirror lag | State becomes healthy, or escalates to unavailable |
| AnalyticsSourceUnavailable | 1 min | Valid heartbeat >300 s; investigate source job, replication slot, mirror and target ingestion | Age ≤300 s; still inspect stale if >120 s |
| AnalyticsFreshnessUnknown | 1 min | Sampler cannot certify its batch; inspect ClickHouse connectivity, grants, malformed rows and clocks | Next valid read, snapshot age ≤65 s |
| AnalyticsSamplerMissing | 1 min | Runtime signal exists but state telemetry has no sample in 2 min | State export resumes for the same live pod |
| AnalyticsServiceMissing | 1 min after 2 min absence | Entire service/runtime telemetry absent; inspect deployment, process, SDK and collector | Runtime signal resumes; then verify sampler state |

Install missing-service rules only when analytics is expected to run. These
rules detect freshness and telemetry loss; the platform deployment/pod alerts
still own a missing individual replica and the collector's own outage. Never
use scrape `up` as the health signal for an OTLP push application.

### Investigation and recovery

1. Check `/health` separately from `/ready`. A live process may have an
   unavailable ClickHouse dependency. Confirm collector and VM ingestion before
   attributing missing metrics to CDC.
2. On unknown, inspect the heartbeat batch through the existing approved reader
   path: one valid timestamp per source, no future timestamp, no duplicate.
   Do not widen service grants or log returned rows to investigate.
3. On stale/unavailable, check the heartbeat writer first: on Kind the pg_cron
   jobs on product-db (`cron.job`, `cron.job_run_details`), then follow
   replication slot and mirror → object transport → target heartbeat view
   ([CDC operations](../../databases/cdc/README.md#operations)); in local-stack
   the fixture's `analytics-heartbeat` container.
   Check all three sources;
   a healthy source cannot certify a different source's data.
4. Correlate a failing overview access record to its business and client spans.
   A `validation` reason needs serving-view/ledger investigation; `limits` needs
   a query-plan/cardinality review, not an automatic limit increase.
5. After repair, require a valid sampler batch and two successive collections
   with expected state. Re-run the API freshness boundary cases. Retain failure
   and recovery evidence in #1266; do not mark G8/G10 complete from a unit test.

Rule checks (Prometheus `promtool`):

```bash
promtool check rules docs/observability/analytics/alerts.yaml
promtool test rules docs/observability/analytics/alerts.test.yaml
```

The tests cover all five firing and recovery paths. The one-minute dwell is a
planned noise guard across two 30-second sampler cycles; the 120/300-second
thresholds come from the API freshness contract. Validate delivery and tune the
dwell from Linux failure/recovery evidence before enabling notifications.

## Linux qualification

Run on the exact PR head, then repeat the release audit on the exact merged
SHAs before tagging:

1. Run `bash scripts/test-integration.sh` in analytics-service with Docker.
   CI uses the existing pinned reusable integration job and its coverage artifact.
2. Start the analytics dark-launch stack with the new registry mounted for C22;
   verify the backend names/units, resource identity and trace/log correlation.
3. With **zero API traffic**, advance heartbeat age through 120/300 s and assert
   the state matrix. Exact 120 is healthy; exact 300 is stale. Correct any gate
   shorthand that uses `>=` for those transitions.
4. Break the heartbeat read, then restore it; verify unknown, omitted lag,
   retained last-success timestamp and recovery. Exercise snapshot expiry,
   source duplicates/missing/future rows, query timeout, limits and validation.
5. Run two replicas with distinct pod resources; confirm separate gauge series,
   one-hot sums, cardinality budget and no duplicate HTTP/DB duration streams.
6. Test SIGTERM with an in-flight sample/request and exporter failure. Verify
   bounded exit, process outcome and final log/trace delivery.
7. Confirm real HTTP → overview → ClickHouse client ancestry and server-side
   ClickHouse query-log trace correlation. C22, G8 performance, G9 browser and
   G10 full A/B/C qualification remain independent runtime gates.

## References

- [ADR-069](../../proposals/adr/ADR-069-serve-commerce-analytics-through-read-only-service/)
- [RFC-0030](../../proposals/rfc/RFC-0030/)
- [Metric contract](../../api/metrics.md)
- [OpenTelemetry database metrics](https://opentelemetry.io/docs/specs/semconv/db/database-metrics/)
- [OpenTelemetry metric API](https://opentelemetry.io/docs/specs/otel/metrics/api/)
