# Rotate Static OpenBAO KV Secret

Use this for KV v2 static secrets such as RustFS backup credentials, service API
keys, or other values that are still not dynamic.

| Rotation type | Current status |
|---|---|
| KV v2 static secret | Deployed today |
| Database dynamic credential | Planned; see [Production Hardening](../production-hardening.md) |

## Generic rotation flow

### 1. Update in OpenBAO

```bash
kubectl port-forward svc/openbao -n openbao 8200:8200
export BAO_ADDR=http://localhost:8200
export BAO_TOKEN=$(kubectl get secret openbao-init-keys -n openbao -o jsonpath='{.data.root_token}' | base64 -d)
bao kv put secret/local/<category>/<service>/<resource> key="new-value"
```

Alternatively, exec into the OpenBAO pod:

```bash
ROOT=$(kubectl get secret -n openbao openbao-init-keys -o jsonpath='{.data.root_token}' | base64 -d)
kubectl exec -n openbao openbao-0 -- sh -c \
  "BAO_TOKEN=$ROOT bao kv put secret/local/<category>/<service>/<resource> key=new-value"
```

### 2. Force ESO refresh

ESO syncs on `refreshInterval: 1h` by default. Force an immediate reconcile:

```bash
kubectl annotate externalsecret <name> -n <namespace> force-sync=$(date +%s) --overwrite
```

For ClusterExternalSecret-managed secrets, annotate the generated ExternalSecret
in each target namespace, or annotate the ClusterSecretStore:

```bash
kubectl annotate clustersecretstore openbao force-sync=$(date +%s) --overwrite
```

### 3. Restart affected pods

```bash
kubectl rollout restart deployment/<name> -n <namespace>
```

## Example: RustFS backup credentials

```bash
ROOT=$(kubectl get secret -n openbao openbao-init-keys -o jsonpath='{.data.root_token}' | base64 -d)
kubectl exec -n openbao openbao-0 -- sh -c \
  "BAO_TOKEN=$ROOT bao kv put secret/local/infra/rustfs/backup-cnpg \
    access_key_id=<new-key> \
    secret_access_key=<new-secret>"

kubectl annotate externalsecret pg-backup-rustfs-cnpg -n product \
  force-sync=$(date +%s) --overwrite
```

## Verify

```bash
kubectl get externalsecret <name> -n <namespace>
kubectl describe externalsecret <name> -n <namespace>
```

If sync fails, see [ESO sync failure](./eso-sync-failure.md).

---

_Last updated: 2026-07-19 — Expanded with full rotation flow from the retired `secrets-management.md`._
