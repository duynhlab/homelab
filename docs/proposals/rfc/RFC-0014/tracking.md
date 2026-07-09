# RFC-0014 consumer-migration tracking

Living checklist for the P2 (write new-name copies) → P3 (retire old) →
P5 (docs sweep) waves. Update the Status column as items land
(`pending → new-written (P2) → soaking → cutover (P3) → done`).
Measured 2026-07-08 against `main` (`a862b6f`).

Label rename applied everywhere: `method→http_request_method`,
`path→http_route`, `code→http_response_status_code`; grouping labels
`app`/`namespace` are preserved by vmagent relabeling (D-3).

## 1. Alerts — `prometheusrules/microservices/alerts.yaml` (17 alerts, 27 metric refs)

| Alert | Old expr basis | New expr basis | Status |
|---|---|---|---|
| MicroserviceDown | `up{job="microservices"}` | D-4: `absent`-style on `go_goroutine_count{app=…}` | new-written (P2) — `MicroserviceDownOtel`, heartbeat-absence on `go_goroutine_count` (D-4; ~5m staleness lag) |
| MicroserviceAllInstancesDown | `up{job="microservices"}` | D-4 (count of live series by app) | new-written (P2) — `MicroserviceAllInstancesDownOtel` |
| MicroserviceHighRestartRate | kube-state-metrics | **unchanged** | n/a ✅ |
| MicroserviceHighErrorRate | `request_duration_seconds_count{code=~"5.."}` | `http_server_request_duration_seconds_count{http_response_status_code=~"5.."}` | new-written (P2) |
| MicroserviceErrorRateCritical | 〃 | 〃 | new-written (P2) |
| MicroserviceNoSuccessfulRequests | `request_duration_seconds_count{code=~"2.."}` | new family, `http_response_status_code=~"2.."` | new-written (P2) |
| MicroserviceHighLatencyP95 | `request_duration_seconds_bucket` | `http_server_request_duration_seconds_bucket` | new-written (P2) |
| MicroserviceHighLatencyP99 | 〃 | 〃 | new-written (P2) |
| MicroserviceLatencyCritical | 〃 | 〃 | new-written (P2) |
| MicroserviceApdexCritical | `_bucket{le="0.5"/"2"}` | new family — **requires the 13-bucket View (le=2)** | new-written (P2) |
| MicroserviceNoTraffic | `request_duration_seconds_count` | new family | new-written (P2) |
| MicroserviceHighRequestsInFlight | `requests_in_flight` | ~~`http_server_active_requests`~~ **not emitted by otelgin v0.69 (verified live 2026-07-09)** — stays on the legacy scrape until otelgin ships it | blocked-upstream |
| MicroserviceRequestsInFlightCritical | 〃 | 〃 | blocked-upstream |
| MicroserviceGoroutineLeak | `go_goroutines` | `go_goroutine_count` | new-written (P2) — deriv() replaces rate() (gauge fix) |
| MicroserviceHighMemoryUsage | `process_resident_memory_bytes` | **cAdvisor** `container_memory_working_set_bytes` (semantic change: RSS → working set, limits-aware) | new-written (P2) — limits-aware working-set % (cAdvisor) |
| MicroserviceHighGCPressure | `go_gc_duration_seconds_sum` | ~~pause metric~~ **no GC-pause metric in the OTel Go runtime set (verified live)** — replaced by `MicroserviceGCThrashOtel` (`go_memory_used_bytes` vs `go_memory_gc_goal_bytes`) | new-written (P2, semantic change) |
| MicroserviceHighGCFrequency | `go_gc_duration_seconds_count` | 〃 folded into `MicroserviceGCThrashOtel` | new-written (P2, folded) |
| *(new)* D-4 pipeline-health | — | `OtelMetricsPipelineExportFailures` on `otelcol_exporter_send_failed_metric_points_total` (needs the collector :8888 self-scrape — verify at P2 soak start) | new-written (P2) |
| *(new)* gRPC east-west pair | — | `GrpcServerHighErrorRateOtel` + `GrpcServerHighLatencyP95Otel` | new-written (P2) |

## 2. Recording rules — `recording-rules.yaml` (15 rules; record names re-mint)

| Old record | New record | Status |
|---|---|---|
| `job_app:request_duration_seconds:rate5m` | `app:http_server_request_duration_seconds:rate5m` | new-written (P2) |
| `job_app:request_duration_seconds:error_rate5m` | `app:http_server_request_duration_seconds:error_rate5m` | new-written (P2) |
| `job_app:request_duration_seconds:client_error_rate5m` | `app:http_server_request_duration_seconds:client_error_rate5m` | new-written (P2) |
| `job_app:request_duration_seconds:error_ratio5m` | `app:http_server_request_duration_seconds:error_ratio5m` | new-written (P2) |
| `job_app:request_duration_seconds:success_ratio5m` | `app:http_server_request_duration_seconds:success_ratio5m` | new-written (P2) |
| `job_app:request_duration_seconds:p50_5m` | `app:http_server_request_duration_seconds:p50_5m` | new-written (P2) |
| `job_app:request_duration_seconds:p95_5m` | `app:http_server_request_duration_seconds:p95_5m` | new-written (P2) |
| `job_app:request_duration_seconds:p99_5m` | `app:http_server_request_duration_seconds:p99_5m` | new-written (P2) |
| `job_app:request_duration_seconds:apdex5m` | `app:http_server_request_duration_seconds:apdex5m` (needs le=0.5 & 2 → View) | new-written (P2) |
| `job_app:requests_in_flight:sum` | ~~`app:http_server_active_requests:sum`~~ **no source metric (otelgin v0.69)** — keeps its legacy source until cutover | blocked-upstream |
| `job_app_path:request_duration_seconds:rate5m` | `app_route:http_server_request_duration_seconds:rate5m` (`by (http_route, http_request_method)`) | new-written (P2) |
| `job_app_path:request_duration_seconds:error_rate5m` | `app_route:http_server_request_duration_seconds:error_rate5m` | new-written (P2) |
| `job_app_path:request_duration_seconds:p95_5m` | `app_route:http_server_request_duration_seconds:p95_5m` | new-written (P2) |
| `job_app:request_size_bytes:rate5m` | `app:http_server_request_body_size_bytes:rate5m` | new-written (P2) |
| `job_app:response_size_bytes:rate5m` | `app:http_server_response_body_size_bytes:rate5m` | new-written (P2) |

> Note: dropping `job_` from the record prefix is deliberate — `job` no longer
> carries the fleet meaning under push (D-3). Anything consuming `job_app:*`
> records is second-order blast radius: grep before P3.

## 3. Sloth SLIs — `helm-charts/charts/mop/templates/slo.yaml` (3 SLIs, 7 refs)

| SLI | Old query basis | New | Status |
|---|---|---|---|
| availability (error+total) | `request_duration_seconds_count{job=~"microservices", code=~"5.."}` | `http_server_request_duration_seconds_count{http_response_status_code=~"5.."}` — **`job` selector must be replaced by an `app!=""`-style selector** | pending |
| latency (error = total − bucket{le=threshold}) | `request_duration_seconds_bucket{le=<thr>}` | new family — thresholds 0.2/0.3/0.5 depend on the 13-bucket View | pending |
| error-rate (4xx\|5xx) | `..._count{code=~"4..|5.."}` | new family/labels | pending |

Every Sloth-generated `slo:sli_error:ratio_rate*` rule and burn-rate alert
regenerates from these — treat the mop bump + homelab rules as one reviewed
pair (risk #3).

## 4. Dashboards — `grafana-dashboards/dashboard/microservices-dashboard.json` (27 panels + 2 template vars, 28 query hits)

| Group | Panels | Status |
|---|---|---|
| Stats row (P50/P95/P99, RPS total/success/error, success/error %, Apdex, total requests) | 9 | pending |
| Endpoint breakdowns (`by (path)` → `by (http_route)`) | 4 | pending |
| Method+endpoint rates / 4xx / 5xx | 4 | pending |
| Latency timeseries (`by (le, path, code)`) | 3 | pending |
| Runtime row (RSS→cAdvisor, goroutines→`go_goroutine_count`, GC ×2) | 4 | pending |
| Network traffic (`*_size_bytes_sum` → `*_body_size_bytes_sum`) | 1 | pending |
| In-flight | 1 | pending |
| Template variables (`label_values(request_duration_seconds_count, namespace/app)` → keyed off `go_goroutine_count`) | 2 | pending |
| *(new)* gRPC east-west row | 1 | pending |

Strategy: create "(new)" copies during P2, swap at P3, delete old at P5.

## 5. Docs sweep (P5) — 19 files / 140 lines referencing `request_duration_seconds`

`docs/observability/`: grafana/dashboard-reference.md · runbooks/observability-deep-dive.md ·
runbooks/microservices-alerts.md · metrics/metrics-apps.md (full rewrite — the
contract doc) · metrics/promql-guide.md · metrics/README.md · slo/README.md ·
metrics/streaming-aggregation.md · grafana/variables.md · alerting/alert-catalog.md ·
alerting/README.md · alerting/slo-burn-rate-alerts.md · slo/annotation-driven-slo-controller.md ·
slo/getting_started.md · slo/fundamentals.md · runbooks/infrastructure-alerts.md ·
observability/README.md · `docs/proposals/rfc/RFC-0013/README.md` (P3 pilot
pattern) + `.vi.md`. Plus exemplar-claim corrections (D-14) and
`legacy-checkout` fence documentation.

## 6. Scrape objects (P3)

| Object | Action | Status |
|---|---|---|
| `servicemonitors/microservices.yaml` | trim selector to checkout-service only (D-13) | pending |
| `podmonitors/podmonitor-order-worker.yaml` | retire | pending |
| vmagent CR | flags D-1/D-2 + relabel D-3 (lands in **P1**, before any push) | **done (P1a)** — usePrometheusNaming, promoteAll=false + allowlist, promoteScopeMetadata=false, regex-guarded relabel |
| otel-collector HelmRelease | metrics pipeline + resources + VL-Stream-Fields header | **metrics pipeline + resources done (P1a)** — VL-Stream-Fields header comes with P4 |

---
_Last updated: 2026-07-09 — P2 wave 1: alerts-otel.yaml + recording-rules-otel.yaml authored (staging-routed); requests_in_flight and GC-pause rows corrected against live OTLP series._
