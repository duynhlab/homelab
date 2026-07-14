# Dynamic Credentials Debug

This is a planned-feature runbook. Use it only after the OpenBAO database secrets engine is actually enabled.

| Status | Meaning |
|---|---|
| Planned | The local Kind cluster does not currently enable `database/` dynamic credentials |
| Source | RFC-0008 production hardening |

```bash
# Check database engine status
bao read database/config/product-db

# Test connection manually
bao write -f database/rotate-root/product-db  # Tests connectivity (rotates root creds)

# Check database role definition
bao read database/roles/product-app-rw

# Manually request credentials (debug)
bao read database/creds/product-app-rw
```

_Last updated: 2026-07-14 - Split from `docs/secrets/README.md` during the runbook refactor._
