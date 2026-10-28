# GitOps / delivery (Flux)

Flux failures are dependency-graph incidents: one red wave freezes everything
downstream via `dependsOn`. Find the head, not a symptom.

## Authoritative docs

- Per-alert: [FluxKustomizationNotReady](../../../../../docs/observability/runbooks/gitops/FluxKustomizationNotReady.md),
  [FluxSourceNotReady](../../../../../docs/observability/runbooks/gitops/FluxSourceNotReady.md),
  [FluxReconciliationFailure](../../../../../docs/observability/runbooks/gitops/FluxReconciliationFailure.md),
  [FluxSuspendedResource](../../../../../docs/observability/runbooks/gitops/FluxSuspendedResource.md).
- Dependency graph + bring-up gotchas: [platform/setup.md](../../../../../docs/platform/setup.md)
  and [AGENTS.md § Gotchas](../../../../../AGENTS.md#gotchas--non-obvious-rules).
- Delivery model: [platform/application-delivery.md](../../../../../docs/platform/application-delivery.md).

## Manifests

- Cluster waves: `kubernetes/clusters/local/` (and `prod/`).
- Rules: `kubernetes/infra/configs/observability/metrics/prometheusrules/gitops/flux-alerts.yaml`.

## Safe commands (read-only first)

```bash
kubectl get kustomization -A | grep -v ' True '   # the Unknown/False set
flux get sources all -A                           # Ready=True, Suspend=False
make flux-status                                   # flux get all -A
make flux-logs                                     # controller logs
```

Read a stuck object's conditions in full before acting:

```bash
kubectl get kustomization -n flux-system <name> \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}  {.message}{"\n"}{end}'
```

## The three real causes

| Message contains | Cause | Where to look |
|---|---|---|
| `dependency '…' is not ready` | Upstream wave | Follow the chain up; this is not the problem |
| `health check failed … timeout waiting for` | Applied, never became healthy | The named object's own controller |
| `failed to build` / `accumulating resources` | The manifests | `make validate`, then the overlay |

## Boundary

- Fix the head of the chain first; mitigating a downstream wave is wasted.
- **Never `kubectl apply` over Flux.** Fix in Git → `make validate` →
  `make flux-push` → `flux reconcile ks <name> -n flux-system --with-source`.
- `Unknown`/progressing states do not page and a cold bring-up retries by
  design — see [triage-and-safety § Flux traps](../triage-and-safety.md#flux-specific-traps).
