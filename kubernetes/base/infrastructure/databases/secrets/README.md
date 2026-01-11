# Database Secrets (CloudNativePG Only)

**⚠️ IMPORTANT**: This directory contains secrets for **CloudNativePG clusters only**.

## Operator Behavior Differences

### Zalando Postgres Operator (Auto-Generated)
**No manual secrets needed!** Zalando operator automatically creates secrets:

- `auth.auth-db.credentials.postgresql.acid.zalan.do` (auth namespace)
- `review.review-db.credentials.postgresql.acid.zalan.do` (review namespace)
- `user.supporting-db.credentials.postgresql.acid.zalan.do` (user namespace)
- `notification.supporting-db.credentials.postgresql.acid.zalan.do` (notification namespace)
- `shipping.supporting-db.credentials.postgresql.acid.zalan.do` (shipping namespace)

**Format:** `<username>.<cluster-name>.credentials.postgresql.acid.zalan.do`

### CloudNativePG Operator (Pre-Create Required)
**Requires pre-created secrets** before cluster bootstrap:

- `product-db-secret` (product namespace) → Used by product-db cluster
- `transaction-db-secret` (cart namespace) → Used by transaction-db cluster (cart database)
- `transaction-db-secret` (order namespace) → Used by transaction-db cluster (order database)

**Format:** Simple Kubernetes Secret with `username` and `password` keys

---

## Secrets in This Directory

| Secret | Namespace | Used By | Operator |
|--------|-----------|---------|----------|
| `product-db-secret.yaml` | product | product-db cluster | CloudNativePG |
| `transaction-db-secret-cart.yaml` | cart | transaction-db cluster | CloudNativePG |
| `transaction-db-secret-order.yaml` | order | transaction-db cluster | CloudNativePG |

---

## Why Pre-Create for CloudNativePG?

CloudNativePG's `.spec.bootstrap.initdb.secret.name` references the secret **at bootstrap time**. The cluster **cannot start** without it.

Example from `product-db.yaml`:
```yaml
bootstrap:
  initdb:
    database: product
    owner: product
    secret:
      name: product-db-secret  # ← Must exist before cluster creation
```

---

## Security Notes

**For Learning/Development (Local Kind):**
- Using simple password: `postgres`
- Safe for local testing

**For Production:**
- Use **External Secrets Operator** or **Sealed Secrets**
- Generate strong random passwords (32+ characters)
- Rotate regularly
- Never commit to git

---

## Verification

**Check Zalando-generated secrets:**
```bash
kubectl get secrets -n auth | grep credentials
# Expected: auth.auth-db.credentials.postgresql.acid.zalan.do
```

**Check CloudNativePG pre-created secrets:**
```bash
kubectl get secret product-db-secret -n product
kubectl get secret transaction-db-secret -n cart
kubectl get secret transaction-db-secret -n order
```

---

## Future: Secret Management Migration

**Phase 8 (Deferred):**
- Migrate to **Sealed Secrets** (encrypt at rest in git)
- Or use **External Secrets Operator** (fetch from Vault/AWS Secrets Manager)

For now, using plain Kubernetes Secrets for learning/local development.
