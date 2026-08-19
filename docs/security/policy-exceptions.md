# Policy Exception Registry

Every Kyverno `PolicyException` MUST appear in this registry with owner, expiry,
and justification. Unlisted exceptions are subject to removal without notice.

Source manifests live in `kubernetes/infra/configs/kyverno/exceptions/`.

| Name | Policies waived | Targets | Owner | Expires | Justification |
|------|------------------|---------|-------|---------|---------------|
| `postgres-operators` | `pss-baseline`, `require-resources` | CNPG Pods in `cloudnative-pg`, `platform`, `product` (the namespaces actually hosting CNPG Clusters) | platform-team | 2026-12-31 | Operator-defined securityContext for postgres lifecycle |
| `openbao` | `pss-baseline` | All Pods in `openbao` | platform-team | 2026-12-31 | OpenBAO needs `IPC_LOCK` (mlock) so unsealed secrets never swap to disk |

PolicyExceptions are accepted **only from the `kyverno` namespace**
(`features.policyExceptions` pinned in the Kyverno HelmRelease) — an exception
manifest in any other namespace is silently ignored.

## Workflow to add an exception

1. Confirm the violation cannot be fixed at the source (chart values, securityContext patch).
2. State the case in the PR description (no GitHub issues on this repo):
   - Policy + rule violated
   - Why fixing upstream is not feasible
   - Proposed expiry (max 1 year)
3. Create `kubernetes/infra/configs/kyverno/exceptions/<name>.yaml` (namespace `kyverno`) with required annotations:
   ```yaml
   metadata:
     annotations:
       platform.duynhlab.dev/owner: <team-or-handle>
       platform.duynhlab.dev/expires-at: "YYYY-MM-DD"
       platform.duynhlab.dev/justification: "<short reason>"
   ```
4. Update this table in the same PR.
5. Add a calendar reminder for the expiry to re-evaluate.

## Workflow to remove an expired or inert exception

1. Pick exceptions from this table where `Expires < today`, or whose target no
   longer matches anything.
2. Re-test the workload — operator may have hardened in the meantime.
3. If still required, renew via PR with a new expiry.
4. If no longer required, delete the manifest and remove the row.

Worked example: `vector-hostpath` (removed 2026-08-19) targeted DaemonSet
`vector-*` in `monitoring`, but Vector deploys into `kube-system` — which
pss-baseline excludes anyway. The exception matched nothing, so it was deleted
rather than renewed.

---

_Last updated: 2026-08-19 — inert `vector-hostpath` deleted (targeted the wrong namespace; kube-system is baseline-excluded), `postgres-operators` rescoped to the namespaces that actually host CNPG Clusters (was matching the retired `auth` ns and three cluster-less ns while missing `platform`), exceptions-namespace pin documented, issue-based workflow replaced with PR-based (no GitHub issues on this repo). Previously 2026-08-12 — `kong-openbao` narrowed to `openbao` (RFC-0024 P2.3)._
