# Rotate Static OpenBAO KV Secret

Use this for KV v2 static secrets such as RustFS backup credentials or other values that are still not dynamic.

| Rotation type | Current status |
|---|---|
| KV v2 static secret | Deployed today |
| Database dynamic credential | Planned; see `production-hardening.md` |

```bash
# Rotate S3 backup credentials
bao kv put secret/local/infra/rustfs/backup-cnpg \
  access_key_id=<new-key> \
  secret_access_key=<new-secret>

# Force ESO to refresh immediately (instead of waiting for refreshInterval)
kubectl annotate externalsecret pg-backup-rustfs-cnpg -n product \
  force-sync=$(date +%s) --overwrite
```

_Last updated: 2026-07-14 - Split from `docs/secrets/README.md` during the runbook refactor._
