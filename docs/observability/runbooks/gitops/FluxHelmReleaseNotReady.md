# FluxHelmReleaseNotReady

| | |
|---|---|
| **Severity** | critical |
| **Category** | gitops |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/gitops/flux-alerts.yaml` |
| **Metrics** | `gotk_resource_info{customresource_kind="HelmRelease", ready="False"}` — via **kube-state-metrics** |
| **Status** | active |
| **Dashboard** | Flux web UI (`flux.duynh.me`) · Observability → GitOps |
| **Local-stack** | not present — the compose stack runs images directly, no Helm |

## Meaning

A `HelmRelease` has reported `Ready=False` for 5 minutes. This cluster runs
**40 of them** — every controller and most platform components (cert-manager,
CNPG, Envoy Gateway, Temporal, ClickHouse operator, Keycloak, the observability
stack, and the `mop` chart per service domain).

The alert carries `chart_name` and `chart_version`, which is usually enough to
tell an upgrade failure from a first-install failure at a glance.

## Impact

Scoped to that release, but the blast radius depends entirely on *which* one. A
failing `mop` release costs one service; a failing `cert-manager` or `cnpg`
release costs everything that depends on certificates or databases, and those
failures surface as unrelated-looking alerts elsewhere.

A release that fails **on upgrade** usually leaves the previous revision running,
so the symptom is "changes are not landing". A release that fails **on install**
leaves nothing running at all.

## Diagnosis

### Read the release, then its history

```bash
flux get helmreleases -A | grep -v ' True '

kubectl get helmrelease -n <ns> <name> \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}  {.message}{"\n"}{end}'

# Which revisions have been attempted, and which one is live
flux get helmreleases -A --status-selector ready=false
helm history <release> -n <ns>
```

### What the reasons mean here

| Reason / message | Cause | Action |
|---|---|---|
| `InstallFailed`, `UpgradeFailed` with a Kubernetes API error | The rendered manifests were rejected | Read the error — often a Kyverno admission denial or a schema mismatch |
| `timeout waiting for condition` | Chart applied; a workload never became ready | Go to the pods, not the chart |
| `chart pull error`, `no chart version found` | Source problem, not release problem | [FluxSourceNotReady](FluxSourceNotReady.md) |
| `RetriesExceeded` / `Stalled` | Flux gave up after `remediation.retries` | Fix the cause, then force a reconcile — retries do not resume on their own |
| `exhausted` / values error | Bad `values:` in the HelmRelease | `make validate`, then the overlay |

**Kyverno is a common and easily-missed cause on this platform.** Admission
requires an explicit namespace, a non-`:latest` pinned image, CPU+memory
requests with a memory limit, and both probes. A chart whose upstream defaults
omit any of those will fail here and nowhere else. Check:

```bash
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -20
kubectl get clusterpolicyreport,policyreport -A 2>/dev/null | grep -i fail
```

### PromQL

```promql
# Alert expr
gotk_resource_info{customresource_kind="HelmRelease", ready="False"} == 1

# Group failures by chart, which usually points at one upstream
count by (chart_name, chart_version, ready) (gotk_resource_info{customresource_kind="HelmRelease"})
```

## Mitigation

1. Fix the cause in git — values, image pin, resources, probes — then
   `make flux-push && make flux-sync`.
2. A `Stalled` release will not retry by itself:
   ```bash
   flux reconcile helmrelease <name> -n <ns> --with-source
   ```
3. Do not `helm upgrade` by hand. Flux owns the release; a manual revision is
   overwritten on the next reconcile and leaves history that disagrees with the
   repository.
4. If a bad upgrade is actively breaking things and the fix is not immediate,
   pinning the previous chart version **in git** is the correct rollback — not
   `helm rollback`.

## Escalation

Critical, but weight it by release. Judge the blast radius before paging:
a controller release (cert-manager, CNPG, Envoy Gateway, Kyverno) is
platform-wide; a single `mop` release is one service and its own RED alerts will
say so more precisely.

If several releases fail at once, look upstream rather than at each release —
a red `HelmRepository` or `HelmChart` produces exactly that pattern.

## Related

- [FluxSourceNotReady](FluxSourceNotReady.md) — chart or repository failures
  surface here as release failures.
- [FluxKustomizationNotReady](FluxKustomizationNotReady.md) — the Kustomization
  that applies this release can be Ready while the release is not.
- [FluxReconciliationFailure](FluxReconciliationFailure.md) — the warning-level
  rule across every kind.
- [FluxSuspendedResource](FluxSuspendedResource.md) — a suspended release is not
  failing, and does not fire this alert.

---
_Last updated: 2026-09-05 — created; the flux-alerts group had no runbooks at all_
