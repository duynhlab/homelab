# Database Secrets

This directory contains Kubernetes Secret manifests for database passwords.

**⚠️ IMPORTANT**: All secret files are gitignored. Do NOT commit passwords to git.

## Creating Secrets

For each database cluster, create a Secret with the password:

```bash
# Example: Auth database secret
kubectl create secret generic auth-db-secret \
  --from-literal=password='your-password-here' \
  -n auth

# Example: Review database secret
kubectl create secret generic review-db-secret \
  --from-literal=password='your-password-here' \
  -n review

# Example: Product database secret (CloudNativePG)
kubectl create secret generic product-db-secret \
  --from-literal=username=product \
  --from-literal=password='your-password-here' \
  -n product

# Example: Transaction database secret (CloudNativePG, for cart and order)
kubectl create secret generic transaction-db-secret \
  --from-literal=username=cart \
  --from-literal=password='your-password-here' \
  -n cart

# Example: Supporting database secret (for user and notification)
kubectl create secret generic supporting-db-secret \
  --from-literal=password='your-password-here' \
  -n user
```

## Secret Names

- `auth-db-secret` - Auth database password (Zalando operator)
- `review-db-secret` - Review database password (Zalando operator)
- `product-db-secret` - Product database password (CloudNativePG operator, includes username)
- `transaction-db-secret` - Transaction database password (CloudNativePG operator, cart + order, includes username)
- `supporting-db-secret` - Supporting database password (Zalando operator, user + notification)

**Note**: CloudNativePG secrets require both `username` and `password` keys, while Zalando secrets only need `password`.

## For Learning/Development

For learning projects, you can use simple passwords:
- `postgres` (default PostgreSQL password)
- `password123`
- Or generate random passwords

**Note**: In production, use strong, randomly generated passwords stored in a secrets management system.
