# Policy Catalog

Authoritative list of Kyverno policies enforced (or audited) on the duynhlab platform.
Source manifests live in `kubernetes/infra/configs/kyverno/cluster-policies/`.
Every PolicyException is registered in [`policy-exceptions.md`](policy-exceptions.md);
the folder hub is [`README.md`](README.md).

Prod modes are **planned** — the production overlay
(`kubernetes/clusters/production/`) is still a stub; only the local Kind
cluster runs these policies today.

| Policy | Tier | Mode (local) | Mode (prod, planned) | failurePolicy | Scope |
|--------|------|--------------|----------------------|---------------|-------|
| `pss-baseline/` (10 `ValidatingPolicy`, vendored from `kyverno/policies` pod-security-vpol/baseline, ADR-078) | 1 | Audit | Enforce | Ignore | All namespaces except 7 infra ns (kube-system, kube-public, kube-node-lease, flux-system, kyverno, cert-manager, external-secrets-system) |
| `pss-restricted-apps` | 1 | **Disabled** | **Disabled** | — | App namespaces (10) — see [Known gaps](#known-gaps--history) |
| `disallow-latest-tag` | 1 | Audit | Enforce | Ignore | All except kube-system, flux-system, kyverno. Three rules: a container tag is required, `:latest` is forbidden, and since ADR-077 an **image volume** (`volumes[].image.reference`) must carry `@sha256:`. `ValidatingPolicy` (CEL) since 2026-09-30, ADR-078 |
| `require-resources` | 1 | Audit | Enforce | Ignore | The 10 app namespaces. `ValidatingPolicy` (CEL) since 2026-09-30, ADR-078 |
| `require-probes` | 1 | Audit | Enforce | Ignore | The 10 app namespaces. `ValidatingPolicy` (CEL) since 2026-09-30, ADR-078 |
| `disallow-default-namespace` | 1 | **Enforce** | Enforce | Fail | All Pods. `ValidatingPolicy` with `validationActions: [Deny]` since 2026-09-30, ADR-078 |
| `verify-images-cosign` | 2 | planned | planned | Ignore | `ghcr.io/duynhlab/*` |
| `require-network-policy` | 2 | planned | planned | Ignore | App namespaces |
| `default-deny-networkpolicy` | 3 | Generate | Generate | n/a | App-tier namespaces (`platform.duynhlab.dev/tier: app`) |
| `add-default-labels` | 3 | planned | planned | Ignore | All Pods |
| `cleanup-completed-pods` | 4 | Enforce | Enforce | n/a | Succeeded/Failed Pods **older than 24h**, swept every 30m (excludes kube-system, flux-system, kyverno). `DeletingPolicy` since 2026-09-30 (ADR-078) |

The cleanup policy needs `cleanup-controller-rbac.yaml` (a ClusterRole
aggregated to Kyverno's cleanup controller) — deployed alongside it, not a
policy itself.

## Acceptance criteria for AI-generated manifests

Any manifest produced by AI agents for this repo MUST satisfy:

1. **Namespace** explicit and not `default`.
2. **Image** of the multi-level form `ghcr.io/duynhlab/<repo>/<image>:<sha>` or `:vX.Y.Z` (e.g. `ghcr.io/duynhlab/product-service/product-service:abc1234`). Never `:latest`.
3. **resources.requests** for `cpu` and `memory` declared on every container.
4. **resources.limits.memory** declared (cpu limit is optional but recommended).
5. **livenessProbe** and **readinessProbe** on the main container.
6. **securityContext** compatible with PSS baseline:
   - no `privileged: true`
   - no `hostNetwork`, `hostPID`, `hostIPC`
   - no `hostPath` volumes (unless covered by PolicyException)
7. *(Aspirational while `pss-restricted-apps` is disabled — see
   [Known gaps](#known-gaps--history).)* For app namespaces, PSS restricted:
   - `runAsNonRoot: true`
   - `allowPrivilegeEscalation: false`
   - `capabilities.drop: [ALL]`
   - `seccompProfile.type: RuntimeDefault`
   - `readOnlyRootFilesystem: true` (write to mounted volumes only)

## Tier definitions

- **Tier 1** — Mandatory baseline, enforced on all environments after audit window.
- **Tier 2** — High-value security (image verify, NetworkPolicy validate). Enforced after Tier 1 stable.
- **Tier 3** — Mutate / Generate convenience policies. Optional but recommended.
- **Tier 4** — Cleanup / housekeeping. Always Enforce.

## Known gaps & history

**`pss-restricted-apps` — disabled since 2026-08-17.** The Kind audit showed
the platform cannot satisfy it: three of the four restricted requirements are
manifest changes, but `runAsNonRoot` fails structurally — the service images
declare no non-root `USER` and the binary is not world-executable, so a pod
pinned to a non-root uid dies at exec. Two further gaps: the `migrate`
initContainer has no `securityContext` (under `mop` it was chart-owned; since
the move to `duynh` it is declared in the domain ResourceSets, so this one is now
a manifest change here), and the `pgdog` chart exposes none.
In Audit mode it blocked nothing and produced 63 standing findings that were
unactionable from this repo — noise that trains readers to ignore the policy
report. The policy is commented out verbatim in
`cluster-policies/pss-restricted-apps.yaml`; its header records the conditions
for re-enabling (a non-root `USER` in the service images first).
**The PSS baseline is unaffected and still runs** (since 2026-09-30 as ten CEL ValidatingPolicies under `cluster-policies/pss-baseline/`).

## NetworkPolicy enforcement

`default-deny-networkpolicy` (a `GeneratingPolicy` since ADR-078) **generates**
a `deny-all-ingress` NetworkPolicy into every namespace labelled
`platform.duynhlab.dev/tier: app` (CREATE or UPDATE; `generateExisting`,
`synchronize`, `orphanDownstreamOnPolicyDelete`). It is the **sole owner** of that
object in those namespaces: the static copies that `network-policies/` also
shipped until 2026-09-30 are gone, and `make validate` refuses one coming back.
The matching explicit allow policies live in
`kubernetes/infra/configs/network-policies/` and are reconciled by the
`network-policies-local` Flux Kustomization (`identity`, which is not app-tier,
keeps its static `deny-all-ingress` there).

**Full reference** — per-service caller matrix, allowed-ingress topology,
kindnet enforcement status, and GitOps wiring:
[`network-policies.md`](network-policies.md).
