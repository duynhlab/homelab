# EnvoyGatewayReconcileErrors

| | |
|---|---|
| **Severity** | warning |
| **Category** | correctness / control plane |
| **Source** | [`envoy-gateway/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/envoy-gateway/alerts.yaml) |
| **Metrics** | `status_update_total{status="failure"}`, `xds_snapshot_create_total{status="failure"}`, `xds_snapshot_update_total{status="failure"}` |

## Meaning

The control plane is running but **failing to finish its job**: either it cannot
write status back to Gateway API resources, or it cannot build/publish an xDS
snapshot. Unlike `EnvoyGatewayControllerDown`, the process is alive — so
liveness, readiness, and Flux all report success.

## Impact

**The running edge config drifts from git.** Someone merges a route, Flux
applies the CR, the controller fails to translate it, and the proxy keeps
serving the previous config. Every downstream assumption — "the route exists
because it is in main" — is now wrong, and nothing else in the pipeline
disagrees with it.

## Diagnosis

```promql
rate(status_update_total{status="failure"}[5m])
rate(xds_snapshot_create_total{status="failure"}[5m])
rate(xds_snapshot_update_total{status="failure"}[5m])

# Snapshot activity should resume after a fix — this is the recovery signal
rate(xds_snapshot_update_total{status="success"}[5m])
```

The controller log names the offending resource; that is faster than reading
every CR:

```bash
kubectl logs -n envoy-gateway -l control-plane=envoy-gateway --tail=300 \
  | grep -iE "translat|reject|invalid|conflict"

# Compare intent with status: a route that is Accepted=False is the drift
kubectl get httproute,securitypolicy,backendtrafficpolicy -A \
  -o custom-columns=KIND:.kind,NS:.metadata.namespace,NAME:.metadata.name,\
CONDS:.status..conditions[*].reason
```

Common causes seen on this platform: a route-level SecurityPolicy without
`mergeType: StrategicMerge` (which replaces the gateway CORS baseline instead of
merging), a `targetRef` naming a resource in another namespace, and two policies
claiming the same target.

### Grafana

**Envoy Gateway Global** — status-update and xDS snapshot panels split by
success/failure; the failure series is this alert, and its return to zero is the
proof of the fix.

## Mitigation

- Fix the rejected resource in git and let Flux reconcile; confirm both the
  resource's `Accepted` condition **and** a fresh successful snapshot before
  closing.
- Verify the actual behaviour, not only the condition. A CORS or JWT policy can
  be Accepted and still not do what was intended — the local-stack audit rows
  (A17–A19) exist for exactly this reason.
- If the failure survives a correct manifest, restart the controller last, not
  first: a restart discards the log evidence that names the resource.

## Escalation

Ticket, escalating to a page if a change that is believed to be live turns out
not to be — a security or auth policy that never reached the fleet is a
production risk regardless of what the dashboards show.
