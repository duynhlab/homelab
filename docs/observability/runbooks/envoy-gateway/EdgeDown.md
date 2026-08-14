# EdgeDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | availability |
| **Source** | [`envoy-gateway/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/envoy-gateway/alerts.yaml) |
| **Metrics** | `up{job="envoy-gateway"}` (data plane, scraped by [`podmonitors/envoy-gateway-proxy.yaml`](../../../../kubernetes/infra/configs/observability/metrics/podmonitors/envoy-gateway-proxy.yaml)) |

## Meaning

An Envoy proxy instance stopped answering its scrape, **or** the whole
`job="envoy-gateway"` series vanished, for 1 minute. The `absent()` half is the
part worth understanding: `up == 0` can only fire for a target Prometheus still
knows about, so a PodMonitor that selects nothing — label drift on
`gateway.envoyproxy.io/owning-gateway-*`, a deleted Gateway, a renamed
namespace — would otherwise be **silent**. Either half means the same thing
operationally: nobody is confirming the edge is alive.

## Impact

The edge is the platform's single entry point (ADR-044). If the fleet is
genuinely down, every API route and both SPAs are unreachable — this is a
full outage, not a degradation. If instead the scrape is broken, traffic may be
fine while every other `Edge*` alert is blind, which is why this pages at
critical either way.

## Diagnosis

Start by deciding **which half** fired — the answer changes everything:

```promql
# Targets that exist and are down (fleet problem)
up{job="envoy-gateway"} == 0

# Nothing exists at all (scrape/selector problem)
absent(up{job="envoy-gateway"})

# Is the edge still serving? Traffic is the ground truth, not `up`
sum(rate(envoy_http_downstream_rq_total{envoy_http_conn_manager_prefix="http-8000"}[1m]))
```

### kubectl

```bash
# The proxy fleet EG generates for the platform Gateway
kubectl get pods -n envoy-gateway \
  -l gateway.envoyproxy.io/owning-gateway-name=platform
kubectl describe pod -n envoy-gateway -l gateway.envoyproxy.io/owning-gateway-name=platform
kubectl logs -n envoy-gateway -l gateway.envoyproxy.io/owning-gateway-name=platform --tail=200

# If the pods are gone, the control plane is what creates them
kubectl get gateway,gatewayclass -A
kubectl get pods -n envoy-gateway -l control-plane=envoy-gateway
```

If the pods are healthy and serving but unscraped, the labels are the suspect:

```bash
kubectl get pods -n envoy-gateway --show-labels | grep owning-gateway
kubectl get podmonitor -n monitoring envoy-gateway-proxy -o yaml | grep -A6 selector
```

### Grafana

**Envoy Global** — the `envoy_server_live` / uptime panels distinguish "no
instances" from "instances restarting". A sawtooth uptime means crashlooping,
which points at config rather than infrastructure.

## Mitigation

- **Fleet down:** the Gateway is reconciled by Flux, so do not hand-edit it.
  Check `make flux-status` for a failed `envoy-gateway-config-local`
  Kustomization; a rejected HTTPRoute or SecurityPolicy can leave the fleet
  without a valid listener. Fix the manifest, not the running pod.
- **Scrape broken:** correct the PodMonitor selector (or the labels EG now
  emits) and confirm the target returns in
  `/targets` before closing the alert. Do not silence this one — a silenced
  `absent()` is indistinguishable from a healthy edge.
- Expect `EdgeNoTraffic` and, once clients time out, `Edge5xxRatioCritical`
  alongside a genuine outage.

## Escalation

Page immediately; this is the whole platform. If the control plane is also
down (`EnvoyGatewayControllerDown`), fix that first — a proxy cannot be
recreated without it.
