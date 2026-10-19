# Dynamic Credentials Debug

Use this when a service runtime password stops syncing or rotating:
`database/static-creds/<svc>-runtime` does not reach the pod,
`ClusterSecretStore/openbao-db` is not ready, or a cluster's
`openbao-db-config` Job fails. `<cluster>` is `platform-db` (namespace
`platform`; user, notification, shipping, review) or `product-db` (namespace
`product`; product, inventory, cart, order, checkout, payment).

| Status | Meaning |
|---|---|
| Deployed (ADR-025, ADR-089) | Database engine at `database/`, one static role `<svc>-runtime` per runtime login on both clusters (ten), `rotation_period` 720h, each cluster through its own `vault_rotator` and `database/config/<cluster>`; ESO reads `database/static-creds/<svc>-runtime` every 15 s |
| Planned | Anything beyond the static-role pattern — dynamic `database/creds/*` roles with per-lease users are **not deployed** |

```bash
# 1. ESO side: store + ExternalSecret health (one copy in the cluster's
#    namespace, one in the service's namespace)
kubectl get clustersecretstore openbao-db
kubectl get externalsecret -A | grep <svc>-runtime
kubectl describe externalsecret <cluster>-<svc>-runtime-secret -n <svc>

# 2. Engine-config side: the cluster's openbao-db-config Job (databases wave)
kubectl get job -n <platform|product> openbao-db-config
kubectl logs -n <platform|product> job/openbao-db-config
# Re-run after a config change: delete the Job and let Flux re-create it
kubectl delete job openbao-db-config -n <platform|product>
flux reconcile kustomization databases-local -n flux-system --with-source
```

For direct engine reads, log in with the staff OIDC method
(`bao login -method=oidc`, `infra-team` — [ADR-062](../../proposals/adr/ADR-062-staff-groups-sso/));
the [generate-root ceremony](./add-secret-live-cluster.md) is the fallback
when the issuer is down. Then:

```bash
# 3. Inspect the engine (never print the password itself)
bao read database/config/<cluster>                  # connection config
bao read database/static-roles/<svc>-runtime        # role + rotation_period
bao read -format=json database/static-creds/<svc>-runtime \
  | jq '.data | {username, last_vault_rotation, ttl}'

# 4. Force a rotation and watch it propagate
bao write -f database/rotate-role/<svc>-runtime
bao token revoke -self                        # revoke a ceremony token when done
```

The ExternalSecret refreshes every **15 s**, and the kubelet then refreshes the
mounted file (up to its sync period). Compare hashes, never values:

```bash
kubectl get secret <cluster>-<svc>-runtime-secret -n <svc> \
  -o jsonpath='{.data.password}' | base64 -d | sha256sum
kubectl exec -n <svc> deploy/<svc> -c <svc> -- sha256sum /etc/db/secret/password
```

The full force-and-verify procedure, including an emergency rotation after a
leak, is the
[service password rotation runbook](../../databases/runbooks/rotate-cnpg-service-password.md).

If the store or ExternalSecret is not Ready, see
[ESO sync failure](./eso-sync-failure.md).
