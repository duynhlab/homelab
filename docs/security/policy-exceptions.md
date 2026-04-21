# Policy Exception Registry

Every Kyverno `PolicyException` MUST appear in this registry with owner, expiry,
and justification. Unlisted exceptions are subject to removal without notice.

Source manifests live in `kubernetes/infra/configs/kyverno/exceptions/`.

| Name | Policies waived | Targets | Owner | Expires | Justification |
|------|------------------|---------|-------|---------|---------------|
| `vector-hostpath` | `pss-baseline` | DaemonSet `vector-*` in `monitoring` | platform-team | 2026-12-31 | Tails container logs from `/var/log/pods` |
| `postgres-operators` | `pss-baseline`, `require-resources` | Spilo + CNPG Pods in DB namespaces | platform-team | 2026-12-31 | Operator-defined securityContext for postgres lifecycle |
| `kong-openbao` | `pss-baseline` | All Pods in `kong`, `openbao` | platform-team | 2026-12-31 | Kong needs `NET_BIND_SERVICE`; OpenBAO needs `IPC_LOCK` |

## Workflow to add an exception

1. Confirm the violation cannot be fixed at the source (chart values, securityContext patch).
2. Open an issue: `[kyverno] exception request: <component>` with:
   - Policy + rule violated
   - Why fixing upstream is not feasible
   - Proposed expiry (max 1 year)
3. Create `kubernetes/infra/configs/kyverno/exceptions/<name>.yaml` with required annotations:
   ```yaml
   metadata:
     annotations:
       platform.duynhlab.dev/owner: <team-or-handle>
       platform.duynhlab.dev/expires-at: "YYYY-MM-DD"
       platform.duynhlab.dev/justification: "<short reason>"
   ```
4. Update this table in the same PR.
5. Add a calendar reminder for the expiry to re-evaluate.

## Workflow to remove an expired exception

1. Pick exceptions from this table where `Expires < today`.
2. Re-test the workload — operator may have hardened in the meantime.
3. If still required, renew with a fresh issue + new expiry.
4. If no longer required, delete the manifest and remove the row.
