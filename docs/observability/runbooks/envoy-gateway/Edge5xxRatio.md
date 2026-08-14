# Edge5xxRatioHigh / Edge5xxRatioCritical

| | |
|---|---|
| **Severity** | warning (>5%) · critical (>15%) |
| **Category** | errors |
| **Source** | [`envoy-gateway/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/envoy-gateway/alerts.yaml) |
| **Metrics** | `edge:rq_5xx_ratio:rate5m` (recording rule over `envoy_http_downstream_rq_xx`) |

## Meaning

The share of **downstream** responses at the edge that are 5xx, over 5 minutes.
Downstream is deliberate: it counts what clients actually received, including
the 5xx **Envoy itself generated** when no healthy upstream existed (response
flags `UF`, `UO`, `UH`) — errors a per-service metric cannot see because the
request never reached a service.

## Impact

Users are getting failures. At >15% most API traffic is failing and the SPAs
are effectively broken; at >5% a route or an upstream is degrading and the
blast radius is still growing.

## Diagnosis

The first question is **whose 5xx**: a backend's, or the edge's own.

```promql
# Which route/cluster is producing them (cluster name = httproute/<ns>/<name>/rule/<n>)
topk(5, edge_cluster:rq_5xx:rate5m)

# Edge-generated vs upstream-served: compare downstream 5xx against upstream 5xx
sum(rate(envoy_http_downstream_rq_xx{envoy_response_code_class="5",envoy_http_conn_manager_prefix="http-8000"}[5m]))
sum(rate(envoy_cluster_upstream_rq_xx{envoy_response_code_class="5"}[5m]))
# downstream >> upstream  →  Envoy is answering 5xx before reaching a backend
```

A downstream/upstream gap means look at connectivity, not at application code:
no healthy endpoint (`EdgeUpstreamUnhealthy` usually fires too), a NetworkPolicy
change, or a Service with no ready pods.

### Logs — the field that decides it

The edge access log carries `response_flags`, and it is the fastest
discriminator in an incident: `-` means the upstream answered 5xx itself, `UF`
is an upstream connect failure, `UH` no healthy upstream, `URX` retry limit,
`UAEX` denied by a filter.

```logsql
{container_name="local-stack-gateway-1"} | json | status >= 500
```

In the cluster, the same lines are in VictoriaLogs under the proxy pod; join to
a trace with `request_id` (it is the `x-request-id` Envoy propagates, so the
owning service's logs carry the same value).

### Grafana

**Envoy Clusters** — per-upstream 5xx and latency; identifies the single route.
**Envoy Global** — response-class mix, to see whether 5xx displaced 2xx or
arrived on top of new traffic.

## Mitigation

- One route only: treat it as that service's incident (its own
  `MicroserviceDown` / DB alerts usually confirm), and consider whether the
  route should be temporarily removed rather than serving 5xx.
- All routes: suspect the edge or a shared dependency (identity, database).
  `EdgeJWKSFetchFailing` turns into 401s rather than 5xx, so it is not this.
- Envoy-generated 5xx with healthy pods: check the generated cluster's endpoints
  (`kubectl get endpointslice -n <svc-ns>`) and any NetworkPolicy that changed.

## Escalation

Critical pages. If the ratio is >15% for more than a few minutes and no single
cluster explains it, roll back the most recent edge or identity change — the
edge has one job and a partial edge failure is not worth debugging live.
