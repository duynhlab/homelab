# Microservices dashboard reference

Use **Microservices → Microservices (OTel)** to locate a service symptom, then
inspect its query and correlate by service/time with traces and logs. This page
indexes the V2 artifact inspected on 2026-10-23; it does not certify live panel results.

The pinned `v0.8.0` artifact was re-inspected on 2026-10-26. Its panel
inventory and layout are checked below; query changes must be verified in Kind.

| Item | Evidence |
|---|---|
| Dashboard | `microservices-monitoring-001-otel` |
| Delivery | [OCI pin](../../../kubernetes/clusters/local/sources/oci/grafana-dashboards-as-code-oci.yaml) → Flux → GrafanaManifest |
| Verified artifact | `v0.8.0`, source `90bacbd6f733bd4441e8d0893fa92e921df19a1b` |
| Digest | `sha256:cfbd2c3822ec92c88d8a7adff03df65b1c73b5582dc1125347246b9113eb4521` |
| Verification | Extracted artifact inspected on 2026-10-26; 43 elements, 7 rows; no live Grafana query |
| Selector | `$app` (the artifact's only dashboard variable) |
| History | [Earlier panel explanations and removed panels](dashboard-reference-legacy.md) |

## Find the right row

| Row | Panels | Question |
|---|---|---|
| Overview & Key Metrics | 11 | Is traffic healthy, and which versions are running? |
| Traffic & Requests | 3 | Which routes and status codes dominate? |
| Errors & Performance | 7 | Where are errors or latency concentrated? |
| Go Runtime & HTTP I/O (OTel) | 5 | Is Go runtime pressure explaining the symptom? |
| gRPC East-West (RED) | 6 | How do client and server gRPC RED compare? |
| gRPC East-West (RED) — Per Callee | 3 | Which outbound gRPC callees are slow or failing? |
| Database (client — otelpgx) | 8 | Are DB calls or pool waits the bottleneck? |

## Panel index

Element keys identify panels in the V2 artifact. The classic dashboard's numeric
IDs and removed-panel descriptions belong to the historical reference.

| Row | Element key | Panel title |
|---|---|---|
| Overview & Key Metrics | `otel-p99` | 99th Percentile Response Success |
| Overview & Key Metrics | `otel-p95` | 95th Percentile Response Success |
| Overview & Key Metrics | `otel-p50` | 50th Percentile Response Success |
| Overview & Key Metrics | `otel-total-rps` | Total RPS (All Requests) |
| Overview & Key Metrics | `otel-success-rps` | Success RPS (2xx) |
| Overview & Key Metrics | `otel-error-rps` | Error RPS (4xx/5xx) |
| Overview & Key Metrics | `otel-success-rate` | Success Rate % (non-5xx) |
| Overview & Key Metrics | `otel-error-rate` | Error Rate % (5xx) |
| Overview & Key Metrics | `otel-apdex` | Apdex Score |
| Overview & Key Metrics | `otel-total-requests` | Total Request |
| Overview & Key Metrics | `otel-running-versions` | Running versions |
| Traffic & Requests | `otel-status-pie` | Status Code Distribution |
| Traffic & Requests | `otel-route-pie` | Total Requests by Endpoint |
| Traffic & Requests | `otel-rps-route` | Request Rate by Endpoint |
| Errors & Performance | `otel-rps-method-route` | Request Rate by Method and Endpoint |
| Errors & Performance | `otel-5xx-ratio` | Server Error Rate by Method and Endpoint (5xx) |
| Errors & Performance | `otel-4xx-service` | Client Errors (4xx) |
| Errors & Performance | `otel-5xx-service` | Server Errors (5xx) |
| Errors & Performance | `otel-route-p95` | Response time 95th percentile |
| Errors & Performance | `otel-route-p50` | Response time 50th percentile |
| Errors & Performance | `otel-route-p99` | Response time 99th percentile |
| Go Runtime & HTTP I/O (OTel) | `otel-go-memory` | Memory In-Use |
| Go Runtime & HTTP I/O (OTel) | `otel-go-alloc` | Memory Allocation Rate |
| Go Runtime & HTTP I/O (OTel) | `otel-go-goroutines` | Goroutines |
| Go Runtime & HTTP I/O (OTel) | `otel-go-gc` | GC Pacing Pressure (used / goal) |
| Go Runtime & HTTP I/O (OTel) | `otel-http-bytes` | Total Network Traffic per Service |
| gRPC East-West (RED) | `otel-grpc-server-rps` | gRPC Server RPS by Method |
| gRPC East-West (RED) | `otel-grpc-client-rps` | gRPC Client RPS by Method |
| gRPC East-West (RED) | `otel-grpc-server-errors` | gRPC Server Error Rate (non-OK) |
| gRPC East-West (RED) | `otel-grpc-client-errors` | gRPC Client Error Rate (non-OK) |
| gRPC East-West (RED) | `otel-grpc-server-p95` | gRPC Server P95 Latency |
| gRPC East-West (RED) | `otel-grpc-client-p95` | gRPC Client P95 Latency |
| gRPC East-West (RED) — Per Callee | `otel-grpc-callee-rps` | gRPC Server RPS per Callee |
| gRPC East-West (RED) — Per Callee | `otel-grpc-callee-error-ratio` | gRPC Server Error Ratio per Callee |
| gRPC East-West (RED) — Per Callee | `otel-grpc-callee-p95` | gRPC Server P95 Latency per Callee |
| Database (client — otelpgx) | `otel-db-p95-service` | DB query p95 by service |
| Database (client — otelpgx) | `otel-db-p95-op` | DB p95 by operation type |
| Database (client — otelpgx) | `otel-db-errors` | DB operation errors |
| Database (client — otelpgx) | `otel-pool-inflight` | Pool in-flight (acquired conns) |
| Database (client — otelpgx) | `otel-pool-saturation` | Pool saturation (acquired / max) |
| Database (client — otelpgx) | `otel-pool-contention` | Pool contention (waiting acquires) |
| Database (client — otelpgx) | `otel-pool-evictions` | Pool dead connections replaced |
| Database (client — otelpgx) | `otel-pool-connect-failures` | Pool connect failures |

## Read a panel correctly

1. Select the service and a UTC window containing known traffic. A blank panel
   is not evidence of zero errors: inspect the query, datasource and matching
   series first.
2. Open the panel's query inspector. Use the rendered artifact's label names
   and interval; do not copy `$namespace`, `$rate` or `$DS_PROMETHEUS` from the
   earlier dashboard, which has a different variable contract.
3. Compare status-code semantics. The artifact distinguishes 4xx traffic from
   server-error ratios; a chart titled “Error RPS (4xx/5xx)” does not have the
   same numerator as a 5xx-only SLO.
4. For histograms, use rate over buckets and retain `le` when aggregating.
   Quantiles cannot be averaged across services. Read the
   [histogram guide](../metrics/histograms.md) for interpretation.
5. Correlate by service and time, then use a concrete trace ID to join logs.
   SDK RED is independent of head sampling; the separate span-metrics board
   describes sampled spans. Neither panel proves business-counter idempotency.

## Verify the rendered dashboard

Follow [Kind K5](../../platform/kind-e2e-audit.md#k5--the-four-signals) and the
[Linux telemetry checklist](../runbooks/telemetry-kind-verification.md).
Verify GrafanaManifest synchronization **and** execute panel queries against
known traffic. A synchronized object proves delivery, not query correctness.
When the OCI pin changes, compare row layout, element keys, variables and query
expressions from that artifact before updating this reference.

Read [dashboards as code](README.md#dashboards-as-code) for ownership and
[Dashboard V2](dashboards-v2.md) for delivery mechanics. The Compose JSON twin
is a different artifact and must be checked independently.
