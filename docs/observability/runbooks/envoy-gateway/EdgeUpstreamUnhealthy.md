# EdgeUpstreamUnhealthy

| | |
|---|---|
| **Severity** | warning |
| **Category** | availability |
| **Source** | [`envoy-gateway/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/envoy-gateway/alerts.yaml) |
| **Metrics** | `envoy_cluster_membership_healthy` < `envoy_cluster_membership_total`, per `envoy_cluster_name` |

## Meaning

For at least one upstream cluster, the edge considers some endpoints unhealthy —
ejected by outlier detection or failing health checks — for 2 minutes. Cluster
names carry the route's identity: `httproute/<namespace>/<name>/rule/<n>`, so
the alert already tells you which route degrades.

## Impact

Capacity for that route is reduced; requests concentrate on the surviving
endpoints. When the count reaches zero the edge answers 503 with response flag
`UH` and `Edge5xxRatioHigh` follows — this alert is the early warning for that.

## Diagnosis

```promql
# Which cluster, and how bad
envoy_cluster_membership_healthy < envoy_cluster_membership_total

# Ejections are the mechanism worth confirming
rate(envoy_cluster_outlier_detection_ejections_active[5m])

# Does the route already show errors?
edge_cluster:rq_5xx:rate5m
```

Then compare Envoy's opinion with Kubernetes':

```bash
kubectl get endpointslice -n <service-ns> -l kubernetes.io/service-name=<service>
kubectl get pods -n <service-ns> -l app=<service> -o wide
kubectl logs -n <service-ns> -l app=<service> --tail=200
```

Two distinct situations look the same in the metric: pods that are genuinely
unready (Kubernetes agrees) and pods Kubernetes considers ready that Envoy has
ejected (only Envoy disagrees). The second points at slow responses or connection
resets rather than a crash — check that service's own latency alerts.

### Grafana

**Envoy Clusters** — per-cluster membership, ejections, and upstream latency in
one row; the healthy-vs-total panel is this alert.

## Mitigation

- Unready pods: it is that service's incident (`MicroserviceDown` and its DB
  alerts usually confirm). The edge recovers on its own once endpoints return.
- Ejected-but-ready pods: look for timeouts and resets; an overloaded instance
  gets ejected before it crashes, which is the system protecting the route.
- Do not disable outlier detection to make the alert stop — that converts a
  degraded route into a route that serves errors.

## Escalation

Ticket while some endpoints remain healthy. Page when a cluster reaches zero
healthy endpoints, because that route is then fully down.
