# FluxReconcileDurationHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | gitops |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/gitops/flux-alerts.yaml` |
| **Metrics** | `gotk_reconcile_duration_seconds_bucket` — exported by the Flux controllers themselves |
| **Status** | active |
| **Dashboard** | Flux web UI (`flux.duynh.me`) · Observability → GitOps |
| **Local-stack** | not present — no Flux in the compose stack |

## Meaning

P99 reconcile duration for some Flux kind has exceeded **5 minutes** for 15
minutes:

```promql
histogram_quantile(0.99,
  sum(rate(gotk_reconcile_duration_seconds_bucket[5m])) by (le, kind, namespace)
) > 300
```

Note the label set is `kind` / `namespace` — *not* the `customresource_kind` /
`exported_namespace` the other rules in this group use, because this metric comes
from the **Flux controllers**, while `gotk_resource_info` comes from
**kube-state-metrics**. Do not copy label selectors between them.

## Impact

Nothing has failed. What has changed is the platform's reaction time: drift
correction, deploys and recovery all now take minutes longer than they should.
Slow reconciliation is also the usual precursor to a health-check timeout, which
*is* a failure —
[FluxKustomizationNotReady](FluxKustomizationNotReady.md) with the message
`health check failed after …`.

## Diagnosis

### Distinguish "big" from "stuck"

A reconcile is legitimately slow when it waits on health checks for objects an
operator creates late — a StatefulSet behind a custom resource, for example.
That is honest waiting, not a defect.

```bash
# Which kinds are slow, and how slow
kubectl get kustomization -A --no-headers | awk '{print $1, $2, $3}'

# Controller-side pressure
kubectl top pods -n flux-system
kubectl logs -n flux-system deploy/kustomize-controller --tail=100 | grep -i 'slow\|timeout\|retry'
```

### The three causes seen here

1. **A wave genuinely waits.** Waves that gate on operator-created objects spend
   real time in `healthChecks`. Expected on a cold bring-up.
2. **Controller resource pressure.** Check CPU and memory on the Flux
   controllers; a throttled controller reconciles everything slowly at once.
3. **Retry storms.** A wave failing and retrying inflates its own duration.
   Check whether a Flux failure alert is firing alongside — if so, that is the
   cause and this is the symptom.

### PromQL

```promql
# Alert expr
histogram_quantile(0.99, sum(rate(gotk_reconcile_duration_seconds_bucket[5m])) by (le, kind, namespace)) > 300

# Compare kinds to see whether it is one or all
histogram_quantile(0.99, sum(rate(gotk_reconcile_duration_seconds_bucket[5m])) by (le, kind))
```

## Mitigation

- **One kind slow** → look at what that kind waits on, not at Flux.
- **Everything slow** → controller resource pressure; check `flux-system` pods.
- **Slow during a cold bring-up** → expected while the dependency chain settles;
  re-check once the cluster is steady rather than acting on it.

Raising the health-check timeout is not a fix. If a wave needs 6 minutes because
the thing it gates on takes 6 minutes, the number is telling the truth.

## Escalation

Warning, and usually informational on its own. It matters as context: if a
critical Flux alert fires later, this alert's history says whether the platform
was already struggling or fell over suddenly.

## Related

- [FluxKustomizationNotReady](FluxKustomizationNotReady.md) — what slow becomes
  when it crosses the health-check timeout.
- [FluxReconciliationFailure](FluxReconciliationFailure.md) — the failure this
  often precedes.

---
_Last updated: 2026-09-05 — created; the flux-alerts group had no runbooks at all_
