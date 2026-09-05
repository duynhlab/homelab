# FluxSuspendedResource

| | |
|---|---|
| **Severity** | warning |
| **Category** | gitops |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/gitops/flux-alerts.yaml` |
| **Metrics** | `gotk_resource_info{suspended="true"}` — via **kube-state-metrics** |
| **Status** | active |
| **Dashboard** | Flux web UI (`flux.duynh.me`) |
| **Local-stack** | not present — no Flux in the compose stack |

## Meaning

A Flux resource has carried `spec.suspend: true` for **24 hours**.

Suspension is a legitimate tool — it is how you stop Flux reverting a manual
change while you debug. This alert exists because the tool is easy to leave
behind, and a forgotten suspension is invisible: the resource reports no error,
shows no failure, and simply stops tracking git.

The 24-hour `for` is the whole design. A suspension during an incident is
expected and should not page; one that outlives the incident is the problem.

## Impact

**Silent drift.** The resource no longer reconciles, so:

- changes merged to git never reach the cluster,
- manual `kubectl` edits are never corrected,
- and the cluster quietly disagrees with the repository, which is the one
  invariant GitOps exists to hold.

Nothing breaks. That is exactly why it is worth alerting on.

## Diagnosis

```bash
# Everything currently suspended
flux get all -A | grep -i suspended
kubectl get kustomization,helmrelease -A -o json \
  | jq -r '.items[] | select(.spec.suspend == true)
           | "\(.kind) \(.metadata.namespace)/\(.metadata.name)"'
```

Then answer one question: **why was it suspended, and is that reason still
true?** Check recent history for the intent:

```bash
git log --oneline -20 -- kubernetes/
```

### PromQL

```promql
# Alert expr
gotk_resource_info{suspended="true"} == 1
```

## Mitigation

If the reason has passed, resume and confirm it converges:

```bash
flux resume kustomization <name> -n flux-system
# or
flux resume helmrelease <name> -n <ns>

kubectl get kustomization -A | grep -v ' True '
```

Expect a burst of reconciliation on resume — the resource applies everything that
changed while it slept, which can be a lot. Watch it rather than walking away.

If the suspension is intentional and long-lived, it does not belong in `suspend`.
Encode the intent in git instead: comment the resource out of its kustomization,
with a note saying why. There is precedent — `mcp-local` has been commented out
of `clusters/local/` since 2026-08-21, which is honest and visible, where a
year-old `suspend: true` would not be.

## Escalation

Warning, and rarely urgent. It becomes urgent when it explains something else: a
fix that "was deployed" but is not running, or a config that keeps reverting.

## Related

- [FluxReconciliationFailure](FluxReconciliationFailure.md) — a suspended
  resource does **not** fire that alert; suspension and failure are different
  states.
- [FluxKustomizationNotReady](FluxKustomizationNotReady.md) — what you may see
  shortly after resuming.

---
_Last updated: 2026-09-05 — created; the flux-alerts group had no runbooks at all_
