# Database Verification Guide

Quick guide to verify database readiness and connection testing.

## Quick Verification Script

Run the automated verification script:

```bash
./scripts/04a-verify-databases.sh
```

This script checks:
- ✅ Cluster status (Ready condition)
- ✅ Database pods are running
- ✅ Databases exist and are accessible
- ✅ Connection testing
- ✅ PgCat poolers status

## Manual Verification Commands

### 1. Check Cluster Status

**Zalando Clusters:**
```bash
# List all Zalando clusters
kubectl get postgresql -A

# Check specific cluster pod
kubectl get pod review-db-0 -n review
kubectl get pod auth-db-0 -n auth
kubectl get pod supporting-db-0 -n user
```

**CloudNativePG Clusters:**
```bash
# List all CloudNativePG clusters
kubectl get cluster -A

# Check cluster details
kubectl get cluster product-db -n product -o yaml
kubectl get cluster transaction-db -n cart -o yaml

# Check cluster pods
kubectl get pods -n product -l cnpg.io/cluster=product-db
kubectl get pods -n cart -l cnpg.io/cluster=transaction-db
```

### 2. Verify Databases Exist

**Zalando Clusters:**
```bash
# Review database
kubectl exec -n review review-db-0 -- psql -U review -d postgres -c "\l" | grep review

# Auth database
kubectl exec -n auth auth-db-0 -- psql -U auth -d postgres -c "\l" | grep auth

# Supporting database (multiple databases)
kubectl exec -n user supporting-db-0 -- psql -U user -d postgres -c "\l" | grep -E "user|notification|shipping"
```

**CloudNativePG Clusters:**
```bash
# Product database
kubectl exec -n product product-db-1 -- psql -U product -d postgres -c "\l" | grep product

# Transaction database (cart + order)
kubectl exec -n cart transaction-db-1 -- psql -U cart -d postgres -c "\l" | grep -E "cart|order"
```

### 3. Test Database Connections

**Direct Connection Test:**
```bash
# Test Review database
kubectl run -it --rm test-review --image=postgres:15-alpine --restart=Never -- \
  psql -h review-db.review.svc.cluster.local -U review -d review -c "SELECT 1;"

# Test Auth database (via PgBouncer)
kubectl run -it --rm test-auth --image=postgres:15-alpine --restart=Never -- \
  psql -h auth-db-pooler.auth.svc.cluster.local -U auth -d auth -c "SELECT 1;"

# Test Product database (via PgCat)
kubectl run -it --rm test-product --image=postgres:15-alpine --restart=Never -- \
  psql -h pgcat.product.svc.cluster.local -U product -d product -c "SELECT 1;"

# Test Cart database (via PgCat)
kubectl run -it --rm test-cart --image=postgres:15-alpine --restart=Never -- \
  psql -h pgcat-transaction.cart.svc.cluster.local -U cart -d cart -c "SELECT 1;"

# Test Order database (via PgCat) - IMPORTANT: Verify order database exists
kubectl run -it --rm test-order --image=postgres:15-alpine --restart=Never -- \
  psql -h pgcat-transaction.cart.svc.cluster.local -U cart -d order -c "SELECT 1;"
```

### 4. Check Order Database (Critical)

**Verify order database exists:**
```bash
# Check if order database was created
kubectl exec -n cart transaction-db-1 -- psql -U cart -d postgres -c "\l" | grep order

# Expected output:
# order | cart | UTF8 | C | C |
```

**If order database doesn't exist:**
```bash
# Check transaction-db cluster status
kubectl get cluster transaction-db -n cart

# Check cluster events for errors
kubectl describe cluster transaction-db -n cart

# Check primary pod logs
kubectl logs -n cart transaction-db-1 --tail=50

# Verify postInitSQL was executed
kubectl get cluster transaction-db -n cart -o yaml | grep -A 5 postInitSQL
```

### 5. Verify PgCat Poolers

**Check PgCat Pods:**
```bash
# Product PgCat
kubectl get pods -n product -l app=pgcat-product
kubectl logs -n product -l app=pgcat-product --tail=50 | grep -i error

# Transaction PgCat
kubectl get pods -n cart -l app=pgcat-transaction
kubectl logs -n cart -l app=pgcat-transaction --tail=50 | grep -i error
```

**Check PgCat Pool Status (via admin port):**
```bash
# Get PgCat pod name
PGCAT_POD=$(kubectl get pods -n cart -l app=pgcat-transaction -o jsonpath='{.items[0].metadata.name}')

# Check pool status
kubectl exec -n cart $PGCAT_POD -- \
  psql -h localhost -p 9930 -U admin -d pgcat -c "SHOW POOLS;"
```

**Expected PgCat Logs (no errors):**
```
INFO  ThreadId(XX) pgcat::pool: Pool 'cart' validated successfully
INFO  ThreadId(XX) pgcat::pool: Pool 'order' validated successfully
```

**If PgCat shows errors:**
```
ERROR ThreadId(XX) pgcat::pool: Shard 0 down or misconfigured: TimedOut
ERROR ThreadId(XX) pgcat::pool: Could not validate connection pool
```
→ This means database doesn't exist or connection failed. Check database first.

### 6. Verify Secrets

**Check all database secrets exist:**
```bash
# CloudNativePG secrets
kubectl get secret product-db-secret -n product
kubectl get secret transaction-db-secret -n cart

# Zalando secrets
kubectl get secret review-db-secret -n review
kubectl get secret auth-db-secret -n auth
kubectl get secret supporting-db-secret -n user
```

**Verify secret contents:**
```bash
# Check transaction-db-secret (should have cart user)
kubectl get secret transaction-db-secret -n cart -o jsonpath='{.data}' | jq
```

### 7. Quick Health Check Commands

**All-in-one status check:**
```bash
# Operators
kubectl get pods -n database

# Zalando clusters
kubectl get postgresql -A

# CloudNativePG clusters
kubectl get cluster -A

# PgCat poolers
kubectl get pods -n product -l app=pgcat-product
kubectl get pods -n cart -l app=pgcat-transaction

# Check order database (critical)
kubectl exec -n cart transaction-db-1 -- psql -U cart -d postgres -c "\l" | grep order
```

## Troubleshooting

### Order Database Not Found

**Symptoms:**
- `kubectl exec ... psql -c "\l" | grep order` returns nothing
- PgCat logs show "Shard 0 down or misconfigured: TimedOut"

**Solution:**
1. Verify `postInitSQL` is in transaction-db CRD:
   ```bash
   kubectl get cluster transaction-db -n cart -o yaml | grep -A 3 postInitSQL
   ```

2. If missing, apply updated CRD:
   ```bash
   kubectl apply -f k8s/postgres-operator-cloudnativepg/crds/transaction-db.yaml
   ```

3. Recreate cluster (⚠️ **WARNING**: This will delete existing data):
   ```bash
   kubectl delete cluster transaction-db -n cart
   kubectl apply -f k8s/postgres-operator-cloudnativepg/crds/transaction-db.yaml
   ```

4. Wait for cluster to be Ready:
   ```bash
   kubectl wait --for=condition=Ready cluster transaction-db -n cart --timeout=600s
   ```

5. Verify order database:
   ```bash
   kubectl exec -n cart transaction-db-1 -- psql -U cart -d postgres -c "\l" | grep order
   ```

### PgCat Connection Timeout

**Symptoms:**
- PgCat logs show "TimedOut" errors
- Pool validation fails

**Solution:**
1. Verify database exists (see above)
2. Check database is accessible:
   ```bash
   kubectl exec -n cart transaction-db-1 -- psql -U cart -d order -c "SELECT 1;"
   ```
3. Restart PgCat:
   ```bash
   kubectl rollout restart deployment/pgcat-transaction -n cart
   ```
4. Check logs again:
   ```bash
   kubectl logs -n cart -l app=pgcat-transaction --tail=50
   ```

### Cluster Not Ready

**Symptoms:**
- `kubectl get cluster` shows status other than "Ready"
- Pods are not Running

**Solution:**
1. Check cluster status:
   ```bash
   kubectl get cluster transaction-db -n cart -o yaml
   kubectl describe cluster transaction-db -n cart
   ```

2. Check pod logs:
   ```bash
   kubectl logs -n cart transaction-db-1 --tail=100
   ```

3. Check events:
   ```bash
   kubectl get events -n cart --sort-by='.lastTimestamp' | grep transaction-db
   ```

## Verification Checklist

After deploying databases, verify:

- [ ] All 5 clusters are Ready
- [ ] All database pods are Running
- [ ] Order database exists in transaction-db cluster
- [ ] All databases are accessible (connection test succeeds)
- [ ] PgCat poolers are running and have no errors
- [ ] PgCat can validate all pools (no timeout errors)
- [ ] Secrets exist for all clusters
- [ ] Services can connect via poolers (when deployed)

## Related Documentation

- [Database Guide](./DATABASE_GUIDE.md) - Complete database integration guide
- [Config Guide](./CONFIG_GUIDE.md) - Environment variables and configuration
- [Audit Report](../../specs/active/postgres-database-integration/AUDIT_REPORT.md) - Issues and fixes

