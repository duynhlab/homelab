# EnvoyGatewayControllerDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | availability / control plane |
| **Source** | [`envoy-gateway/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/envoy-gateway/alerts.yaml) |
| **Metrics** | `up{job="envoy-gateway-controller"}` ([`servicemonitors/envoy-gateway-controller.yaml`](../../../../kubernetes/infra/configs/observability/metrics/servicemonitors/envoy-gateway-controller.yaml)) |

## Meaning

The Envoy Gateway **control plane** is unreachable (or unscraped) for 5 minutes.
The data plane keeps serving from the config it already has, which is exactly
why this needs its own alert: traffic looks perfect while the platform has
quietly become unconfigurable.

## Impact

Two consequences, both delayed:

- **No Gateway API change reconciles.** A merged HTTPRoute, SecurityPolicy, or
  certificate rotation does nothing. Flux reports success — it applied the CR;
  nobody translated it.
- **A restarted proxy comes back empty.** The proxy fetches config over xDS at
  startup, so any pod that restarts while the controller is down cannot serve.
  That turns a controller outage into a traffic outage on the next node drain.

## Diagnosis

```promql
up{job="envoy-gateway-controller"} == 0 or absent(up{job="envoy-gateway-controller"})

# Is the data plane still fine? (it usually is — say so explicitly)
up{job="envoy-gateway"}
sum(rate(envoy_http_downstream_rq_total[5m]))
```

```bash
kubectl get pods -n envoy-gateway -l control-plane=envoy-gateway
kubectl describe pod -n envoy-gateway -l control-plane=envoy-gateway
kubectl logs -n envoy-gateway -l control-plane=envoy-gateway --tail=300

# Is it Flux's doing? The HelmRelease owns this deployment
make flux-status
```

### Grafana

**Envoy Gateway Global** — watchable queue depth and xDS snapshot counters flat
at zero while the proxy dashboards keep moving is the picture of this alert.

## Mitigation

- Crashlooping on config: read the log for the rejected resource; the fix is a
  manifest change, not a restart.
- OOM or resource pressure: `Resources Monitor` dashboard, then adjust the
  HelmRelease values under review — this is a Kyverno-guarded workload, so
  requests/limits must stay set.
- **Do not restart proxies while the controller is down.** A restarted proxy has
  no config to fetch, so the safe order is: controller healthy first, proxies
  after.

## Escalation

Page. It is critical not because users are hurting now, but because the next
routine event (deploy, drain, cert rotation) turns it into an outage — and
`EnvoyGatewayReconcileErrors` will not fire while the controller is fully down.
