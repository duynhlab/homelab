# FluxReconciliationFailure

| | |
|---|---|
| **Severity** | warning |
| **Category** | gitops |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/gitops/flux-alerts.yaml` |
| **Metrics** | `gotk_resource_info{ready="False"}` — via **kube-state-metrics** |
| **Status** | active |
| **Dashboard** | Flux web UI (`flux.duynh.me`) · Observability → GitOps |
| **Local-stack** | not present — no Flux in the compose stack |

## Meaning

The catch-all: **any** Flux custom resource has been `Ready=False` for 10
minutes, regardless of kind. It matches all five kinds present on this cluster —
`Kustomization`, `HelmRelease`, `HelmChart`, `HelmRepository`, `OCIRepository`.

It deliberately overlaps the three critical rules. Those fire at 5–10 minutes on
the kinds whose failure is unambiguous; this one is the net that catches
everything else, including kinds nobody wrote a specific rule for.

## Impact

Depends entirely on the kind and the resource. Read `customresource_kind` and
`name` from the labels before assuming anything — this alert alone does not tell
you whether one service or the whole platform stopped converging.

## Diagnosis

```bash
# Everything Flux considers not-Ready, all kinds
flux get all -A --status-selector ready=false
# or the make target
make flux-status
```

Then follow the kind-specific runbook:

| `customresource_kind` | Runbook |
|---|---|
| `Kustomization` | [FluxKustomizationNotReady](FluxKustomizationNotReady.md) |
| `HelmRelease` | [FluxHelmReleaseNotReady](FluxHelmReleaseNotReady.md) |
| `OCIRepository`, `HelmRepository`, `HelmChart` | [FluxSourceNotReady](FluxSourceNotReady.md) |

### PromQL

```promql
# Alert expr
gotk_resource_info{ready="False"} == 1

# Everything, by kind and state — the fastest read of GitOps health
count by (customresource_kind, ready) (gotk_resource_info)
```

## Mitigation

Handled by the kind-specific runbook above. If this alert fires while none of the
three critical ones do, the failing resource is a kind they do not cover — read
its conditions directly.

## Escalation

Warning. If a critical Flux alert is firing at the same time, this one is its
shadow: silence it mentally and work the critical.

Worth knowing: `ready` also takes the value **`Unknown`** for a resource that is
still progressing, and no rule in this group matches `Unknown`. A resource that
retries forever without settling produces silence here, so a GitOps surface that
looks clean during an incident should still be checked with
`kubectl get kustomization -A`.

## Related

- [FluxKustomizationNotReady](FluxKustomizationNotReady.md),
  [FluxHelmReleaseNotReady](FluxHelmReleaseNotReady.md),
  [FluxSourceNotReady](FluxSourceNotReady.md) — the specific rules this one
  generalises.
- [FluxSuspendedResource](FluxSuspendedResource.md) — suspended is not failing.
- [FluxReconcileDurationHigh](FluxReconcileDurationHigh.md) — slow, not failed.

---
_Last updated: 2026-09-05 — created; the flux-alerts group had no runbooks at all_
