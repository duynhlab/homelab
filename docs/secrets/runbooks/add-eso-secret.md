# Add ESO-Managed Secret

Use this when adding a new static secret that External Secrets Operator should
sync from OpenBAO KV v2 into a Kubernetes Secret.

| Prerequisite | Doc |
|---|---|
| Path naming convention | [Secret organization](../README.md#secret-organization) |
| OpenBAO bootstrap flow | [OpenBAO initial setup](./openbao-initial-setup.md) |

## 1. Add to OpenBAO bootstrap script

Edit `kubernetes/infra/configs/openbao/openbao-bootstrap/configmap.yaml`:

```bash
# Follow path convention: secret/{env}/{category}/{service}/{resource}
bao kv put secret/local/services/my-service/credentials key1="value1" key2="value2"
```

For **prod-only operator-supplied secrets** (not in Git), seed after cluster
create — see
[OpenBAO initial setup § Step 7](./openbao-initial-setup.md#step-7--seed-bootstrap-only-cloudflare-token-operator).

## 2. Create ExternalSecret (namespace-specific)

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <secret-name>
  namespace: <namespace>
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: openbao
    kind: ClusterSecretStore
  target:
    name: <secret-name>
    creationPolicy: Owner
    deletionPolicy: Retain
  data:
    - secretKey: <k8s-key>
      remoteRef:
        key: secret/data/local/<category>/<service>/<resource>
        property: <openbao-key>
```

Place the manifest alongside the workload it serves — DB secrets under
`kubernetes/infra/configs/databases/clusters/*/secrets/`; shared secrets under
`kubernetes/infra/configs/secrets/cluster-external-secrets/`.

## 3. Or use ClusterExternalSecret (shared across namespaces)

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterExternalSecret
metadata:
  name: <secret-name>
spec:
  namespaceSelector:
    matchLabels:
      <label-key>: <label-value>
  refreshTime: 1h
  externalSecretSpec:
    refreshInterval: 1h
    secretStoreRef:
      name: openbao
      kind: ClusterSecretStore
    target:
      name: <secret-name>
    data:
      - secretKey: <k8s-key>
        remoteRef:
          key: secret/data/local/<category>/<component>/<resource>
          property: <openbao-key>
```

For backup credentials, use label `platform.duynhlab/backup: "cnpg"` — see
[Backup secrets](../README.md#backup-secrets-clusterexternalsecret).

## 4. Deploy

```bash
make validate
make flux-push && make flux-sync
```

## 5. Verify

```bash
kubectl get externalsecret <secret-name> -n <namespace>
kubectl describe externalsecret <secret-name> -n <namespace>
kubectl get secret <secret-name> -n <namespace>
```

If the ExternalSecret is not Ready, see [ESO sync failure](./eso-sync-failure.md).

---

_Last updated: 2026-07-19 — Split from the retired `secrets-management.md` during the secrets docs merge._
