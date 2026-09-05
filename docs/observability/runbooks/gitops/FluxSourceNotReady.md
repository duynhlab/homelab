# FluxSourceNotReady

| | |
|---|---|
| **Severity** | critical |
| **Category** | gitops |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/gitops/flux-alerts.yaml` |
| **Metrics** | `gotk_resource_info{customresource_group=~"source.toolkit.fluxcd.io", ready="False"}` — via **kube-state-metrics** |
| **Status** | active |
| **Dashboard** | Flux web UI (`flux.duynh.me`) · Observability → GitOps |
| **Local-stack** | not present — no Flux in the compose stack |

## Meaning

A Flux **source** has been unable to fetch for 10 minutes. The rule matches the
whole `source.toolkit.fluxcd.io` group, which on this cluster means four kinds:

| Kind | Count | What it fetches |
|---|---|---|
| `HelmChart` | 20 | A chart resolved from a repository, created by Flux itself |
| `HelmRepository` | 17 | Upstream chart indexes (jetstack, cnpg, altinity, grafana, …) |
| `OCIRepository` | 16 | This platform's own manifests, pushed by `make flux-push` |
| `GitRepository` | 0 | none — delivery here is OCI, not git-pull |

This is the **root of the delivery tree**. Nothing below a red source can
reconcile, because there is nothing to reconcile from.

## Impact

Delivery stops for every consumer of that source. An `OCIRepository` failure is
the widest: `infrastructure-oci` and `apps-oci` feed the entire Kustomization
chain, so a stale or unfetchable artifact freezes the platform's whole desired
state. A single `HelmRepository` failure is narrower — only the charts drawn from
it.

Nothing running goes down. What is lost is the ability to change or self-heal.

## Diagnosis

### Identify kind and reason

```bash
flux get sources all -A
kubectl get ocirepository,helmrepository,helmchart -A --no-headers | grep -v ' True '

kubectl get <kind> -n <ns> <name> \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}  {.message}{"\n"}{end}'
```

### The three failures that actually happen here

**1. OCIRepository cannot pull from the local registry.** This platform pushes
manifests to `homelab-registry` (`localhost:5050` from the host,
`homelab-registry:5000` from inside the cluster). If the registry container was
lost — a `kind delete` removes it — every artifact is gone even though the
Kustomizations still reference it.

```bash
docker ps --format '{{.Names}}' | grep homelab-registry   # must exist
make flux-push                                            # re-publish all three artifacts
```

**2. HelmRepository index fetch fails.** Upstream is unreachable or the index
moved. Check the URL in the object and try it from a pod, not from the laptop —
the cluster's egress is what matters.

**3. HelmChart cannot resolve a version.** Usually a pinned version that no
longer exists in the index, or an index that has not refreshed. Flux creates
these objects itself; the fix is in the `HelmRelease` that asks for the version.

### PromQL

```promql
# Alert expr
gotk_resource_info{customresource_group=~"source.toolkit.fluxcd.io", ready="False"} == 1

# Which kind is failing
count by (customresource_kind, ready) (gotk_resource_info{customresource_group=~"source.toolkit.fluxcd.io"})
```

## Mitigation

1. **OCIRepository** → confirm the registry exists, then `make flux-push`
   followed by `make flux-sync`.
2. **HelmRepository** → `flux reconcile source helm <name> -n <ns>`; if the index
   is genuinely gone, the pin must move in git.
3. **HelmChart** → fix the version in the owning `HelmRelease`; do not edit the
   `HelmChart`, which Flux regenerates.

Verify recovery on the object, not on the alert:

```bash
flux get sources all -A | grep -v ' True '   # should print nothing
```

## Escalation

Critical. A red source is upstream of everything, so expect
[FluxKustomizationNotReady](FluxKustomizationNotReady.md) and
[FluxHelmReleaseNotReady](FluxHelmReleaseNotReady.md) to follow within minutes —
they are downstream noise, not separate incidents.

One caveat before escalating: these alerts read `gotk_resource_info` from
**kube-state-metrics**. If KSM itself is down the whole Flux alert group goes
silent rather than red, so a suspiciously quiet GitOps surface during an incident
deserves a `kubectl get kustomization -A` before it is believed.

## Related

- [FluxKustomizationNotReady](FluxKustomizationNotReady.md) — the immediate
  downstream consumer.
- [FluxHelmReleaseNotReady](FluxHelmReleaseNotReady.md) — HelmReleases fail when
  their `HelmChart` or `HelmRepository` cannot resolve.
- [FluxReconciliationFailure](FluxReconciliationFailure.md) — warning-level rule
  covering every Flux kind, including sources.

---
_Last updated: 2026-09-05 — created; the flux-alerts group had no runbooks at all_
