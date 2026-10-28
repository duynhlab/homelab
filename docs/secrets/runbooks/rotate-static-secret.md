# Rotate Static OpenBAO KV Secret

Use this for KV v2 static secrets such as RustFS backup credentials, service API
keys, or other values that are still not dynamic.

| Rotation type | Current status |
|---|---|
| KV v2 static secret | Deployed today |
| Database static role (ADR-025, ADR-089) | Deployed for all ten service runtime logins — not a KV secret; rotate with `bao write -f database/rotate-role/<svc>-runtime` per the [service password rotation runbook](../../databases/runbooks/rotate-cnpg-service-password.md). Migrator, `db_authz`, Temporal and Keycloak passwords stay KV static and follow this page. See [OpenBAO architecture §5.2](../openbao.md#52-database-secrets-engine--dynamic-credentials) |

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

## Example: a RustFS consumer key

Each RustFS consumer has its own IAM user, created from its OpenBAO path by the
setup CronJob (`secret/local/infra/rustfs/{cnpg,pyroscope,clickhouse,peerdb}`;
the table in [openbao.md](../openbao.md#51-kv-v2--static-secrets) lists the
consumer behind each). Rotating one means re-seeding the path, letting RustFS
learn the new secret, then restarting the consumer.

Mint a temporary root token first via the
[break-glass ceremony](./add-secret-live-cluster.md) (steps 1–3, inside
`openbao-0` — the stored `root_token` is inert and cannot write). Then, still
inside `openbao-0` with `BAO_TOKEN` exported:

```bash
bao kv put secret/local/infra/rustfs/cnpg \
  access_key_id=cnpgbackup \
  secret_access_key=<new-secret>
bao token revoke -self   # revoke the temporary root when done
```

Force both copies of the path to sync, then re-run the setup script so the IAM
user gets the new secret (every call is create-or-replace):

```bash
kubectl annotate externalsecret rustfs-consumer-credentials -n rustfs \
  force-sync=$(date +%s) --overwrite
kubectl annotate clusterexternalsecret pg-backup-rustfs-cnpg \
  force-sync=$(date +%s) --overwrite
kubectl -n rustfs create job --from=cronjob/setup-pg-backup-buckets rotate-$(date +%s)
kubectl -n rustfs logs -f job/rotate-<ts>   # ends with the isolation matrix
```

Then restart the consumer (Barman reads the Secret per backup, so CNPG needs no
restart; Pyroscope and PeerDB take the key as env, so `kubectl rollout restart`
their Deployments).

## Verify

```bash
kubectl get externalsecret <name> -n <namespace>
kubectl describe externalsecret <name> -n <namespace>
```

If sync fails, see [ESO sync failure](./eso-sync-failure.md).
