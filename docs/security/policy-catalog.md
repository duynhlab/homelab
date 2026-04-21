# Policy Catalog

Authoritative list of Kyverno policies enforced (or audited) on the duynhlab platform.
Source manifests live in `kubernetes/infra/configs/kyverno/cluster-policies/`.

| Policy | Tier | Mode (local) | Mode (prod) | failurePolicy | Scope |
|--------|------|--------------|-------------|---------------|-------|
| `pss-baseline` | 1 | Audit | Enforce | Ignore | All namespaces except platform |
| `pss-restricted-apps` | 1 | Audit | Enforce | Ignore | App namespaces only (8) |
| `disallow-latest-tag` | 1 | Audit | Enforce | Ignore | All except platform |
| `require-resources` | 1 | Audit | Enforce | Ignore | App namespaces only |
| `require-probes` | 1 | Audit | Enforce | Ignore | App namespaces only |
| `disallow-default-namespace` | 1 | **Enforce** | Enforce | Fail | All Pods |
| `cleanup-completed-pods` | 4 | Enforce | Enforce | n/a | Cleanup, every 30m |
| `verify-images-cosign` | 2 | planned | planned | Ignore | `ghcr.io/duynhlab/*` |
| `require-network-policy` | 2 | planned | planned | Ignore | App namespaces |
| `default-deny-networkpolicy` | 3 | planned | planned | Ignore | Tenant namespaces |
| `add-default-labels` | 3 | planned | planned | Ignore | All Pods |

## Acceptance criteria for AI-generated manifests

Any manifest produced by AI agents for this repo MUST satisfy:

1. **Namespace** explicit and not `default`.
2. **Image** of the form `ghcr.io/duynhlab/<service>:<sha>` or `:vX.Y.Z`. Never `:latest`.
3. **resources.requests** for `cpu` and `memory` declared on every container.
4. **resources.limits.memory** declared (cpu limit is optional but recommended).
5. **livenessProbe** and **readinessProbe** on the main container.
6. **securityContext** compatible with PSS baseline:
   - no `privileged: true`
   - no `hostNetwork`, `hostPID`, `hostIPC`
   - no `hostPath` volumes (unless covered by PolicyException)
7. For app namespaces also satisfy PSS restricted:
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
