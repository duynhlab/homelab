# Dynamic Credentials Debug

Use this when the ADR-025 database static-role pilot misbehaves: the
`notification` password stops syncing, `ClusterSecretStore/openbao-db` is not
ready, or the `openbao-db-config` Job fails.

| Status | Meaning |
|---|---|
| Deployed (ADR-025 pilot) | Database engine at `database/`, static role `notification` on `platform-db`, `rotation_period` 720h, read path `database/static-creds/notification` |
| Planned | Anything beyond the static-role pattern — dynamic `database/creds/*` roles with per-lease users are **not deployed** |

```bash
# 1. ESO side: store + ExternalSecret health
kubectl get clustersecretstore openbao-db
kubectl get externalsecret platform-db-notification-secret -n notification
kubectl describe externalsecret platform-db-notification-secret -n notification
# (a platform-namespace copy of the same ExternalSecret exists too)

# 2. Engine-config side: the openbao-db-config Job (databases wave, ns platform)
kubectl get job -n platform openbao-db-config
kubectl logs -n platform job/openbao-db-config
# Re-run after a config change: delete the Job and let Flux re-create it
kubectl delete job openbao-db-config -n platform
flux reconcile kustomization databases-local -n flux-system --with-source
```

For direct engine reads, log in with the staff OIDC method
(`bao login -method=oidc`, `infra-team` — [ADR-062](../../proposals/adr/ADR-062-staff-groups-sso/));
the [generate-root ceremony](./add-secret-live-cluster.md) is the fallback
when the issuer is down. Then:

```bash
# 3. Inspect the engine (inside openbao-0, BAO_TOKEN exported)
bao read database/config/platform-db          # connection config
bao read database/static-roles/notification   # role + rotation_period
bao read database/static-creds/notification   # current username/password + ttl

# 4. Force a rotation and watch it propagate
bao write -f database/rotate-role/notification
bao token revoke -self                        # revoke the ceremony token when done
```

The ExternalSecret refreshes every **1m**, so within a minute of rotation
`platform-db-notification-secret` should carry the new password:

```bash
kubectl get secret platform-db-notification-secret -n notification \
  -o jsonpath='{.data.password}' | base64 -d
```

If the store or ExternalSecret is not Ready, see
[ESO sync failure](./eso-sync-failure.md).

---

_Last updated: 2026-08-27 — admin access via ADR-062 staff OIDC login. 2026-08-19: rewritten to the deployed ADR-025 pilot._
