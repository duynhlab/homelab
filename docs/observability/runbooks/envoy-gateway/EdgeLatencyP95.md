# EdgeLatencyP95High / EdgeLatencyP95Critical

| | |
|---|---|
| **Severity** | warning (>1000 ms) · critical (>2000 ms) |
| **Category** | latency |
| **Source** | [`envoy-gateway/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/envoy-gateway/alerts.yaml) |
| **Metrics** | `edge:latency_ms:p95_5m` (histogram quantile over `envoy_http_downstream_rq_time`) |

## Meaning

The 95th percentile of **downstream** request duration — first byte in to last
byte out, as measured by the proxy — is above the threshold. Envoy's histograms
are in **milliseconds**, unlike the application's OTLP histograms in seconds;
mixing the two is the classic misreading of this alert.

Downstream duration includes time spent **inside the edge** (JWT verification,
CORS, rate limiting) as well as the upstream's own time, which is what makes
the split below the whole diagnosis.

## Impact

Users wait. Past ~2 s the SPAs start showing spinners long enough that people
retry, which adds load to a system already slow — the reason the critical
threshold pages rather than tickets.

## Diagnosis

Split edge time from upstream time. That single comparison tells you which team
owns the problem:

```promql
# Downstream (what the client felt) vs upstream (what the backend took)
edge:latency_ms:p95_5m
topk(5, edge_cluster:upstream_latency_ms:p95_5m)

# Edge overhead ≈ downstream − upstream. Sustained and large → the edge itself.
```

- **Upstream ≈ downstream** → a backend is slow. Follow that service's own
  latency alert and DB metrics; the edge is only reporting.
- **Downstream ≫ upstream** → the edge is the cost. Look at what runs per
  request there: JWKS fetches (`envoy_http_jwt_authn_*`), rate-limit buckets,
  and connection churn (`envoy_http_downstream_cx_total` climbing while
  `rq_total` is flat means clients are reconnecting per request).

### Grafana

**Envoy Global** for the downstream histogram, **Envoy Clusters** for the
per-upstream one; comparing the two panels side by side is the same split as
the PromQL above.

### Traces

The edge is the trace root (`platform.envoy-gateway-system`), so one slow trace
shows the hop that consumed the time without any guessing. Sampling is
ParentBased at 100% locally and lower in the cluster — pick a trace from the
slow window rather than a fresh request.

## Mitigation

- Backend-owned: scale or fix the slow service; nothing at the edge helps.
- Edge-owned: check whether a JWKS endpoint is timing out (the fetch is
  synchronous on cache miss), and whether the proxy is CPU-saturated
  (`Resources Monitor` dashboard).
- Do not raise the thresholds to clear the page. They are SLO-derived; a
  threshold change belongs in a reviewed manifest change with the reasoning.

## Escalation

Critical pages. Escalate to the owning service team when upstream latency
explains it; keep it with platform when the gap is at the edge.
