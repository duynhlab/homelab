# Rotate Static OpenBAO KV Secret

Use this for KV v2 static secrets such as RustFS backup credentials, service API
keys, or other values that are still not dynamic.

| Rotation type | Current status |
|---|---|
| KV v2 static secret | Deployed today |
| Database static role (ADR-025 pilot) | Deployed for `notification` only — rotate now with `bao write -f database/rotate-role/notification` (ceremony token); other services remain KV static. See [OpenBAO architecture §5.2](../openbao.md#52-database-secrets-engine--dynamic-credentials) |

## Generic rotation flow

### 1. Update in OpenBAO

> ⚠️ The `root_token` in `openbao-init-keys` is an **inert copy** — the real
> root is revoked at the end of bootstrap (RFC-0008), so it cannot write.
> Mint a temporary root via the break-glass ceremony first:
> [Add or write a KV secret on a live cluster](./add-secret-live-cluster.md),
> then run the `bao kv put` from its step 4.

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

Mint a temporary root token first via the
[break-glass ceremony](./add-secret-live-cluster.md) (steps 1–3, inside
`openbao-0` — the stored `root_token` is inert and cannot write). Then, still
inside `openbao-0` with `BAO_TOKEN` exported:

```bash
bao kv put secret/local/infra/rustfs/backup-cnpg \
  access_key_id=<new-key> \
  secret_access_key=<new-secret>
bao token revoke -self   # revoke the temporary root when done
```

Then force the ExternalSecret to pick it up:

```bash
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

_Last updated: 2026-08-19 — RustFS example uses the break-glass ceremony token (stored root_token is inert); database static-role row updated to the deployed ADR-025 pilot._
