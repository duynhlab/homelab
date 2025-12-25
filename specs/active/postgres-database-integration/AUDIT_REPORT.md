# Audit Report: PostgreSQL Database Integration

**Task ID:** postgres-database-integration  
**Audited:** 2025-12-23 (Updated)  
**Spec:** spec.md/plan.md  
**Status:** 🔴 **CRITICAL ISSUE FOUND** - Order database missing, deploy script doesn't handle existing clusters

---

## Executive Summary

Đã audit toàn diện implementation và phát hiện **1 CRITICAL issue**: Order database không tồn tại mặc dù CRD đã có `postInitSQL`. 

**Database Status Check:**
- ✅ Review DB: `review` database exists
- ✅ Auth DB: `auth` database exists  
- ✅ Supporting DB: `user`, `notification`, `shipping` databases exist
- ✅ Product DB: `product` database exists
- ❌ Transaction DB: `cart` database exists, **`order` database MISSING**

**Root Cause:** Cluster được tạo TRƯỚC KHI có `postInitSQL` trong CRD (created: 06:22:44, CRD updated later). `postInitSQL` chỉ chạy khi cluster được bootstrap lần đầu. Deploy script không check và recreate cluster nếu thiếu database.

**Quick Stats:**
- 🔴 Critical: 1 (Order database missing - deploy script gap)
- 🟠 Major: 0
- 🟡 Minor: 1 (Verify script only reports, doesn't fix)
- ⚪ Outdated: 0

---

## 🔍 Review Comments

| ID | Severity | Location | Issue | Status |
|:--:|:--------:|:---------|:------|:------|
| #6 | 🔴 CRIT | `scripts/04-deploy-databases.sh:163-215` | **Deploy Script Gap**: Script không check order database sau khi apply CRD. Nếu cluster đã tồn tại (tạo trước khi có postInitSQL), order database sẽ không được tạo | 🔴 **OPEN** |
| #7 | 🔴 CRIT | `scripts/04a-verify-databases.sh:289-295` | **Verify Script Gap**: Script chỉ báo lỗi nhưng không fix. Nên auto-create hoặc hướng dẫn recreate cluster | 🟡 **MINOR** |

---

## Detailed Findings

### #6: [Critical] Deploy Script Doesn't Handle Existing Clusters with Missing Databases

**Location:** `scripts/04-deploy-databases.sh:163-215`  
**Requirement:** Spec FR-015 - "Update Deployment Scripts"  
**Plan:** Task 7.1 - "Create deployment script for database infrastructure"

**Current Code:**
```bash
# Apply CloudNativePG CRDs
echo "Applying CloudNativePG database CRDs..."
kubectl apply -f "$PROJECT_ROOT/k8s/postgres-operator-cloudnativepg/crds/"

# Wait for clusters to be ready
echo "Waiting for database clusters to be ready (this may take 5-10 minutes)..."
# ... wait loop ...
```

**Issue:**
1. Script apply CRD với `postInitSQL` để tạo order database
2. NHƯNG nếu cluster đã tồn tại (tạo trước khi có `postInitSQL`), `postInitSQL` sẽ KHÔNG chạy
3. Script không check xem order database có tồn tại không
4. Script không recreate cluster nếu thiếu database
5. Kết quả: Order database không bao giờ được tạo

**Evidence:**
- Cluster created: `2025-12-23T06:22:44Z`
- Cluster ready: `2025-12-23T06:27:55Z`
- CRD generation: `3` (đã update 2 lần sau khi tạo)
- CRD có `postInitSQL`: ✅ Có trong spec
- Database `order` tồn tại: ❌ KHÔNG (chỉ có `cart`)
- Logs: Nhiều lỗi `"database \"order\" does not exist"`

**Root Cause:**
CloudNativePG's `postInitSQL` chỉ chạy khi cluster được **bootstrap lần đầu**. Nếu cluster đã tồn tại trước khi `postInitSQL` được thêm vào CRD, SQL statements sẽ không bao giờ chạy.

**Recommended Fix:**
Thêm logic vào deploy script để:
1. Sau khi apply CRD và cluster ready
2. Check xem order database có tồn tại không
3. Nếu thiếu → Delete và recreate cluster (để `postInitSQL` chạy)
4. Wait for cluster ready again

**Code to Add (after line 215):**
```bash
# Check if transaction-db cluster has order database
echo "Checking if transaction-db cluster has order database..."
if kubectl get cluster transaction-db -n cart &> /dev/null; then
    # Get primary pod
    primary_pod=$(kubectl get pods -n cart -l cnpg.io/cluster=transaction-db,role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -z "$primary_pod" ]; then
        primary_pod=$(kubectl get pods -n cart -l cnpg.io/cluster=transaction-db -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    fi
    
    if [ -n "$primary_pod" ]; then
        # Check if order database exists
        if ! kubectl exec -n cart "$primary_pod" -- psql -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='order'" 2>/dev/null | grep -q 1; then
            echo "WARN: Order database not found in existing cluster"
            echo "INFO: Recreating cluster to run postInitSQL (this will delete existing data)..."
            
            # Delete cluster
            kubectl delete cluster transaction-db -n cart --wait=false
            
            # Wait for deletion
            echo "Waiting for cluster deletion..."
            kubectl wait --for=delete cluster transaction-db -n cart --timeout=120s 2>/dev/null || true
            
            # Reapply CRD
            echo "Reapplying transaction-db CRD..."
            kubectl apply -f "$PROJECT_ROOT/k8s/postgres-operator-cloudnativepg/crds/transaction-db.yaml"
            
            # Wait for cluster to be ready again
            echo "Waiting for transaction-db cluster to be ready after recreation..."
            kubectl wait --for=condition=Ready cluster transaction-db -n cart --timeout=300s 2>/dev/null || {
                echo "WARN: transaction-db may not be ready yet after recreation"
            }
        else
            echo "SUCCESS: Order database already exists"
        fi
    fi
fi
```

**Impact:**
- ✅ Deploy script sẽ tự động fix missing order database
- ✅ Idempotent: Safe to run multiple times
- ✅ Follows CRD specification (recreate để postInitSQL chạy)
- ⚠️ Data loss: Recreating cluster sẽ xóa data hiện tại (acceptable for dev/learning)

---

### #7: [Minor] Verify Script Only Reports, Doesn't Fix

**Location:** `scripts/04a-verify-databases.sh:289-295`  
**Requirement:** Spec FR-015 - "Update Deployment Scripts"  
**Plan:** Task 8.4 - "Verification and testing"

**Current Code:**
```bash
# Check order database (NEW - created via postInitSQL)
check_database_exists "transaction-db" "cart" "order" "cart" "cloudnativepg"
if [ $? -eq 0 ]; then
    test_connection "transaction-db" "cart" "order" "cart" "cloudnativepg"
else
    echo "    WARN: Order database not found - may need to recreate cluster with postInitSQL"
    echo "    INFO: Apply updated CRD: kubectl apply -f k8s/postgres-operator-cloudnativepg/crds/transaction-db.yaml"
fi
```

**Issue:**
- Script chỉ báo lỗi và hướng dẫn manual fix
- Không tự động fix (recreate cluster)
- User phải tự chạy lệnh

**Recommended Fix:**
Option 1: Keep as-is (verify script chỉ verify, không fix)
Option 2: Add auto-fix logic (recreate cluster nếu thiếu database)

**Impact:**
- 🟡 Minor: Verify script đúng mục đích (verify only)
- Có thể cải thiện UX bằng cách auto-fix

---

## Root Cause Analysis

### Timeline of Events:

1. **06:22:44** - Cluster `transaction-db` được tạo lần đầu
   - CRD lúc đó KHÔNG có `postInitSQL`
   - Chỉ tạo `cart` database

2. **06:27:55** - Cluster ready
   - Chỉ có `cart` database
   - `order` database không tồn tại

3. **Sau đó** - CRD được update với `postInitSQL`
   - Generation tăng từ 1 → 3
   - `postInitSQL` được thêm vào spec
   - NHƯNG cluster đã tồn tại → `postInitSQL` không chạy

4. **Hiện tại** - Verify script chạy
   - Phát hiện `order` database không tồn tại
   - Báo lỗi nhưng không fix

### Why postInitSQL Doesn't Run:

CloudNativePG's `postInitSQL` feature:
- ✅ Chạy khi cluster được **bootstrap lần đầu**
- ❌ KHÔNG chạy khi cluster đã tồn tại và CRD được update
- ❌ KHÔNG thể trigger lại `postInitSQL` trên existing cluster

**Solution:** Recreate cluster để `postInitSQL` chạy.

---

## 🛠️ Recommended Actions

**Option A: Fix Deploy Script** (Recommended)
- Fix issue: #6
- Estimated time: 30 minutes
- Steps:
  1. Add check for order database after cluster ready
  2. Recreate cluster if database missing
  3. Wait for cluster ready again
- Command: "Fix #6"

**Option B: Fix Verify Script** (Optional)
- Fix issue: #7
- Estimated time: 15 minutes
- Steps:
  1. Add auto-fix logic to verify script
  2. Recreate cluster if database missing
- Command: "Fix #7"

**Option C: Manual Fix** (Quick)
- Recreate cluster manually:
  ```bash
  kubectl delete cluster transaction-db -n cart
  kubectl apply -f k8s/postgres-operator-cloudnativepg/crds/transaction-db.yaml
  kubectl wait --for=condition=Ready cluster transaction-db -n cart --timeout=300s
  ```
- Verify: `kubectl exec -n cart transaction-db-1 -- psql -U postgres -d postgres -c "\l" | grep order`

---

## Verification Checklist

After fixes are applied:
- [ ] Deploy script checks for order database after cluster ready
- [ ] Deploy script recreates cluster if order database missing
- [ ] Order database exists after cluster recreation
- [ ] PgCat order pool validation succeeds
- [ ] Order service can connect successfully
- [ ] Verify script reports order database exists

**Verification Commands:**
```bash
# Check order database exists
kubectl exec -n cart transaction-db-1 -- psql -U postgres -d postgres -c "\l" | grep order

# Check PgCat logs (should see no errors)
kubectl logs -n cart -l app=pgcat-transaction --tail=50 | grep -i error

# Run deploy script (should auto-fix if missing)
./scripts/04-deploy-databases.sh

# Run verify script (should pass)
./scripts/04a-verify-databases.sh
```

---

## Positive Findings

✅ **Correctly Implemented:**
- ✅ **All CRDs correct**: CRD có `postInitSQL` để tạo order database
- ✅ **All other databases exist**: 
  - Review: `review` ✅
  - Auth: `auth` ✅
  - Supporting: `user`, `notification`, `shipping` ✅
  - Product: `product` ✅
  - Transaction: `cart` ✅
- ✅ **Service configs correct**: Cart và Order services có DB config đúng
- ✅ **PgCat config correct**: Có pools cho cả cart và order databases
- ✅ **Verify script**: Phát hiện được missing database
- ✅ **Deploy script**: Apply CRD correctly
- ✅ **Clusters ready**: Tất cả clusters đều Ready và accessible
- ✅ **Pods running**: Tất cả database pods đều Running

---

📋 **Audit Report Ready**

**Summary:**
- 🔴 Critical: 1 issue (Deploy script doesn't handle existing clusters)
- 🟠 Major: 0 issues
- 🟡 Minor: 1 issue (Verify script only reports, doesn't fix)
- ⚪ Outdated: 0 spec updates needed

**Recommended action:** Fix #6 (Deploy script gap)

**To fix issues:**
- "Fix #6" - Add check and recreate logic to deploy script
- "Fix #7" - Add auto-fix to verify script (optional)
- "Fix all critical" - Fix #6

**Status:** 🔴 **Critical Issue Found** - Deploy script needs update to handle existing clusters

---

*Audit report generated with SDD 3.0 - Thorough investigation completed*
