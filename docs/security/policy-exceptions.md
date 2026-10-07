# Policy Exception Registry

Every Kyverno `PolicyException` MUST appear in this registry with owner, expiry,
and justification. Unlisted exceptions are subject to removal without notice.

Source manifests live in `kubernetes/infra/configs/kyverno/exceptions/`.

| Name | Policies waived | Targets | Owner | Expires | Justification |
|------|------------------|---------|-------|---------|---------------|
| — | — | — | — | — | **No exception is active (2026-09-30).** |

**Removed 2026-09-30 as inert (ADR-078 step 3).** Before migrating the last two
legacy exceptions, the ten CEL PSS baseline checks were run against every pod in
the cluster with **no** exception loaded. All 83 pods passed, including the 8
the exceptions had covered:
- `openbao`: its pods do not request `IPC_LOCK`, because the chart leaves mlock
  off. The fixture `tests/pss-baseline` shows that an `IPC_LOCK` pod *does* fail
  `disallow-capabilities`, so the check works and the exception was simply not
  needed. If mlock is turned on, add a CEL exception for `disallow-capabilities`
  on the `openbao` pods only.
- `postgres-operators`: `application=cnpg` matched no pod. The CNPG operator
  pod passes baseline on its own.

PolicyExceptions are accepted **only from the `kyverno` namespace**
(`features.policyExceptions` pinned in the Kyverno HelmRelease) — an exception
manifest in any other namespace is silently ignored.

## Workflow to add an exception

1. Confirm the violation cannot be fixed at the source (chart values, securityContext patch).
2. State the case in the PR description (no GitHub issues on this repo):
   - Policy + rule violated
   - Why fixing upstream is not feasible
   - Proposed expiry (max 1 year)
3. Create `kubernetes/infra/configs/kyverno/exceptions/<name>.yaml` (namespace `kyverno`) as a
   `policies.kyverno.io/v1` `PolicyException`. It names the **policy** it waives; CEL
   policies have no rule names. `spec.expiresAt` makes the expiry real, and the
   annotations keep the registry fields:
   ```yaml
   apiVersion: policies.kyverno.io/v1
   kind: PolicyException
   metadata:
     name: <name>
     namespace: kyverno
     annotations:
       platform.duynhlab.dev/owner: <team-or-handle>
       platform.duynhlab.dev/expires-at: "YYYY-MM-DD"
       platform.duynhlab.dev/justification: "<short reason>"
   spec:
     expiresAt: "YYYY-MM-DDT00:00:00Z"
     policyRefs:
       - name: disallow-capabilities   # the one check that fails, not the whole baseline
         kind: ValidatingPolicy
     matchConditions:
       - name: target
         expression: "object.metadata.namespace == '<ns>' && object.metadata.labels[?'app.kubernetes.io/name'].orValue('') == '<app>'"
   ```
   Add it to `exceptions/kustomization.yaml`, and add a fixture row proving the `skip`.
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
