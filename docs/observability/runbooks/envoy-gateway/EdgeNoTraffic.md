# EdgeNoTraffic

| | |
|---|---|
| **Severity** | warning |
| **Category** | traffic |
| **Source** | [`envoy-gateway/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/envoy-gateway/alerts.yaml) |
| **Metrics** | `envoy_http_downstream_rq_total` rate, guarded by "had traffic in the last hour" and "fleet is up" |

## Meaning

The edge served nothing for 10 minutes, on a fleet that is up and that *was*
serving within the hour. Those two guards are what make this a signal instead of
noise: without them it would fire every quiet night, and it would duplicate
`EdgeDown` during a real outage.

## Impact

This is the failure mode where **everything looks healthy and nothing works**.
Pods ready, `up == 1`, dashboards green — and no request arriving, because a
listener or a route stopped matching. No liveness-based alert can see it; only
the absence of traffic can.

## Diagnosis

```promql
# Confirm the silence is at the edge itself
sum(rate(envoy_http_downstream_rq_total{envoy_http_conn_manager_prefix="http-8000"}[5m]))

# Are listeners even accepting connections?
sum(envoy_listener_downstream_cx_active)
```

Then check what the control plane believes it programmed — a rejected resource
silently stops matching:

```bash
kubectl get httproute -A -o custom-columns=\
NS:.metadata.namespace,NAME:.metadata.name,PARENTS:.status.parents[*].conditions[*].type
kubectl get gateway -n envoy-gateway platform -o yaml | yq '.status'
kubectl logs -n envoy-gateway -l control-plane=envoy-gateway --tail=200 | grep -iE "reject|error"
```

A recently merged HTTPRoute or SecurityPolicy is the usual cause: a policy with
the wrong `targetRef`, or a route whose parent `sectionName` no longer exists.
In local-stack the same evidence is in the gateway container's log and
`gateway/eg/*.yaml`.

### Grafana

**Envoy Global** — request rate at zero while uptime keeps climbing is this
alert's signature, and distinguishes "no traffic" from "just restarted".

## Mitigation

- Fix the rejected resource and let Flux reconcile; never patch the generated
  Envoy config, which is rebuilt from the CRs on the next xDS snapshot.
- If the real cause is client-side (DNS, ingress address, SPA origin), the edge
  is fine — say so in the incident record, or the alert loses trust.

## Escalation

Ticket — unless it lands inside a deploy window, in which case treat it as a
failed rollout and roll the edge change back.
