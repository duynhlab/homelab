# FluxKustomizationNotReady

| | |
|---|---|
| **Severity** | critical |
| **Category** | gitops |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/gitops/flux-alerts.yaml` |
| **Metrics** | `gotk_resource_info{customresource_kind="Kustomization", ready="False"}` — exported by **kube-state-metrics**, not by the Flux controllers |
| **Status** | active |
| **Dashboard** | Flux web UI (`flux.duynh.me`) · Observability → GitOps |
| **Local-stack** | not present — no Flux in the compose stack |

## Meaning

A Flux `Kustomization` has reported `Ready=False` for 5 minutes. This cluster
declares **29 of them** in `kubernetes/clusters/local/`, wired into a dependency
chain, so one failure is rarely one failure — it is a wave head.

**Know what this alert does not see.** `gotk_resource_info` carries three `ready`
values: `True`, `False` and **`Unknown`**. A Kustomization that is *progressing*
sits at `Unknown`, and this alert ignores it. A wave that retries forever without
ever settling to `False` will therefore never page. Confirm with the real object
before trusting silence:

```bash
kubectl get kustomization -A | grep -v ' True '
```

## Impact

Whatever that Kustomization applies has stopped converging, and **everything
downstream of it in the dependency chain stays where it is**. Because Flux gates
on `dependsOn`, a failure high in the chain (`controllers-local`,
`secrets-local`) silently freezes a dozen waves that are themselves perfectly
healthy — they are simply never reached.

Already-running workloads keep serving. What stops is change: no new manifests,
no drift correction, no recovery.

## Diagnosis

### Find the head of the wave, not a symptom

```bash
# Everything not Ready, with the reason column
kubectl get kustomization -A --no-headers | grep -v ' True '

# The one that matters: read its conditions in full
kubectl get kustomization -n flux-system <name> \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}  {.message}{"\n"}{end}'
```

A message of `dependency '<other>' is not ready` means **this is not the
problem** — go to `<other>` and repeat.

### Distinguish the three real causes

| Message contains | Cause | Where to look |
|---|---|---|
| `dependency '…' is not ready` | Upstream wave | Follow the chain up |
| `health check failed after …: timeout waiting for` | Objects applied, but never became healthy | The named object's own controller |
| `failed to build`, `accumulating resources`, `did not find expected key` | The manifests themselves | `make validate`, then the kustomize overlay |

The middle row is the one that misleads. A health-check timeout means Flux
applied everything successfully and then waited — the manifests are fine, the
workload is not.

### PromQL

```promql
# Alert expr
gotk_resource_info{customresource_kind="Kustomization", ready="False"} == 1

# The whole GitOps surface at a glance
count by (customresource_kind, ready) (gotk_resource_info)
```

## Mitigation

1. **Fix the head of the chain first.** Mitigating a downstream wave while its
   dependency is red accomplishes nothing.
2. Force a re-reconcile once the cause is addressed:
   ```bash
   flux reconcile kustomization <name> -n flux-system --with-source
   # or, for the whole cluster:
   make flux-sync
   ```
3. If the failure is a health-check timeout on an object an operator creates
   late, the wave may simply need longer — check whether the object has since
   become healthy, and consider whether the timeout is honest rather than
   raising it reflexively.
4. If the manifests are at fault, fix them in git and `make flux-push` — do not
   `kubectl apply` over Flux, which will be reverted on the next reconcile and
   leaves the cluster disagreeing with the repository.

## Escalation

Critical, but read the wave before waking anyone. A single red Kustomization
with a dozen `dependency … is not ready` behind it is **one** incident, and the
dozen are noise. Escalate on the head.

A cold bring-up produces transient failures here by design — some waves time out
once and pass on retry. Treat a `False` that clears within one retry cycle as
bring-up noise, not an incident; treat one that persists across retries as real.

## Related

- [FluxSourceNotReady](FluxSourceNotReady.md) — if the source is red, every
  Kustomization reading it will follow. Check there first.
- [FluxHelmReleaseNotReady](FluxHelmReleaseNotReady.md) — a Kustomization that
  applies HelmReleases can be Ready while the releases underneath are not.
- [FluxReconciliationFailure](FluxReconciliationFailure.md) — the broader
  warning-level rule across every Flux kind.
- [FluxReconcileDurationHigh](FluxReconcileDurationHigh.md) — slow, not failed;
  often the precursor.

---
_Last updated: 2026-09-05 — created; the flux-alerts group had no runbooks at all_
