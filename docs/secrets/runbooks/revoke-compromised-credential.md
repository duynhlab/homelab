# Revoke Compromised Credential

Use this during incident response when a token, static secret, or future leased dynamic credential is suspected compromised.

```bash
# Single credential (known lease ID)
bao lease revoke database/creds/product-app-rw/abc123xyz

# All credentials for a role (incident response)
bao lease revoke -prefix database/creds/product-app-rw/

# Verify the PostgreSQL user was dropped
kubectl exec -n product product-db-1 -- \
  psql -U postgres -c "\du" | grep "v-k8s-product"
```

_Last updated: 2026-07-14 - Split from `docs/secrets/README.md` during the runbook refactor._
