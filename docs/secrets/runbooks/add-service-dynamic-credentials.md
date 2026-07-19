# Add Service Dynamic Credentials

This is a planned-feature onboarding note for the future OpenBAO database engine rollout. Today services use ESO-backed KV v2 static credentials.

| Status | Meaning |
|---|---|
| Planned | Do not follow this as current local Kind procedure |
| Current service-secret flow | Use [Secrets hub](../README.md#secret-organization) and [Add ESO-managed secret](./add-eso-secret.md) |

```bash
# 1. Create OpenBAO policy
bao policy write service-newservice - <<EOF
path "database/creds/newservice-app-rw" {
  capabilities = ["read"]
}
EOF

# 2. Create Kubernetes auth role
bao write auth/kubernetes/role/newservice \
  bound_service_account_names=newservice \
  bound_service_account_namespaces=newservice \
  policies=service-newservice \
  ttl=1h

# 3. Configure DB role in OpenBAO database engine
bao write database/roles/newservice-app-rw \
  db_name=product-db \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; ..." \
  password_policy=db-strong \
  default_ttl=1h \
  max_ttl=24h

# 4. Create ExternalSecret manifest in kubernetes/infra/configs/databases/clusters/product-db/secrets/
```

_Last updated: 2026-07-14 - Split from `docs/secrets/README.md` during the runbook refactor._
