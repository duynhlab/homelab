# Task Review & Priority Order

> **Date**: December 14, 2025  
> **Status**: Task 4.3 (Update Service Handlers) - **NOT STARTED**

---

## ✅ Completed Tasks

### Infrastructure (Phase 1-2)
- ✅ Task 4.1: DatabaseConfig struct created
- ✅ Task 4.2: database.go files created (8 services)
- ✅ Task 3.2: SQL migration scripts created (8 files)
- ✅ Task 5.2: Helm values updated (7 services)
- ✅ Task 7.1: Deployment script created

### Files Created
- ✅ `services/pkg/config/config.go` - DatabaseConfig added
- ✅ `services/internal/{service}/core/database.go` - 8 files created
- ✅ `services/migrations/{service}/001_init_schema.sql` - 8 files created
- ✅ `k8s/postgres-operator-*/` - Operator configs
- ✅ `k8s/pgcat/*/` - PgCat poolers
- ✅ `scripts/04-deploy-databases.sh` - Deployment script

---

## ❌ Task 4.3: Update Service Handlers - NOT STARTED

### Current Status

**Code Analysis:**
- ❌ `main.go` files: **NO database connection initialization**
- ❌ `service.go` files: **Still using mock data** (e.g., `if req.Username == "admin" && req.Password == "password"`)
- ❌ `handler.go` files: **No database integration**

**Example from `services/internal/auth/logic/v1/service.go`:**
```go
// Mock authentication logic
if req.Username == "admin" && req.Password == "password" {
    user := domain.User{
        ID:       "1",
        Username: req.Username,
        Email:    "admin@example.com",
    }
    // ... returns mock data
}
```

**What Needs to Be Done:**
1. Initialize database in `main.go`: `database.Connect()`
2. Replace mock data in `logic/v1/service.go` and `logic/v2/service.go` with SQL queries
3. Update handlers to use database-backed services
4. Add error handling for database errors
5. Test all endpoints

---

## 📋 Recommended Task Order (Before Task 4.3)

### Phase A: Prerequisites (Must Do First)

#### 1. **Task 4.4: Add PostgreSQL Driver** ⚠️ **BLOCKER**
- **Status**: ❌ Not done
- **Action**: User action required
- **Command**: `cd services && go get github.com/lib/pq`
- **Why First**: Cannot compile database code without this dependency
- **Time**: 5 minutes

#### 2. **Task 3.3: Create Init Containers for Migrations** ⚠️ **IMPORTANT**
- **Status**: ❌ Not done
- **Why Before 4.3**: Database tables must exist before services can query them
- **What**: Update `charts/templates/deployment.yaml` to run migrations on pod startup
- **Time**: 2-3 hours
- **Dependencies**: Task 3.2 ✅ (SQL scripts already created)

#### 3. **Task 5.1: Create Kubernetes Secrets** ⚠️ **BLOCKER**
- **Status**: ❌ Not done
- **Action**: User action required
- **Why Before 4.3**: Services need database passwords to connect
- **Time**: 10 minutes
- **Secrets Needed**: 5 secrets (auth, review, product, transaction, supporting)

---

### Phase B: Database Infrastructure (Can Do in Parallel)

#### 4. **Deploy Databases** (User Action)
- **Status**: ❌ Not done
- **Command**: `./scripts/04-deploy-databases.sh`
- **Why**: Databases must be running before services can connect
- **Time**: 10-15 minutes (waiting for clusters to be ready)

---

### Phase C: Implementation (After Prerequisites)

#### 5. **Task 4.3: Update Service Handlers** 🎯 **MAIN TASK**
- **Status**: ❌ Not started
- **Dependencies**: 
  - ✅ Task 4.1 (DatabaseConfig)
  - ✅ Task 4.2 (database.go files)
  - ✅ Task 3.2 (SQL scripts)
  - ⏳ Task 4.4 (PostgreSQL driver) - **BLOCKER**
  - ⏳ Task 3.3 (Init containers) - **IMPORTANT**
  - ⏳ Task 5.1 (Secrets) - **BLOCKER**
- **Time**: 8-12 hours
- **Services**: 9 services × 2 versions (v1 + v2) = 18 service files to update

**Implementation Steps:**
1. For each service (auth, user, product, cart, order, review, notification, shipping):
   - Update `main.go`: Add `database.Connect()` call
   - Update `logic/v1/service.go`: Replace mock with SQL queries
   - Update `logic/v2/service.go`: Replace mock with SQL queries
   - Update `web/v1/handler.go`: Ensure it uses service layer (usually already does)
   - Update `web/v2/handler.go`: Ensure it uses service layer
2. Add error handling for database errors
3. Add database tracing spans (optional)
4. Test each endpoint

---

### Phase D: Testing & Validation (After Implementation)

#### 6. **Task 5.3: Test Helm Deployment**
- **Status**: ❌ Not done
- **Time**: 1-2 hours
- **Dependencies**: Task 4.3 ✅

#### 7. **Task 8.1: Test Database Connections**
- **Status**: ❌ Not done
- **Time**: 2-3 hours
- **Dependencies**: Task 4.3 ✅

#### 8. **Task 8.2: Test k6 Load Testing**
- **Status**: ❌ Not done
- **Time**: 3-4 hours
- **Dependencies**: Task 4.3 ✅, Task 8.1 ✅

---

## 🎯 Recommended Execution Order

### Step 1: Prerequisites (Do These First)
```bash
# 1. Add PostgreSQL driver (5 min)
cd services && go get github.com/lib/pq

# 2. Deploy databases (15 min)
./scripts/04-deploy-databases.sh

# 3. Create secrets (10 min)
kubectl create secret generic auth-db-secret --from-literal=password='postgres' -n auth
kubectl create secret generic review-db-secret --from-literal=password='postgres' -n review
kubectl create secret generic product-db-secret --from-literal=password='postgres' -n product
kubectl create secret generic transaction-db-secret --from-literal=password='postgres' -n cart
kubectl create secret generic supporting-db-secret --from-literal=password='postgres' -n user
```

### Step 2: Init Containers (2-3 hours)
- Update `charts/templates/deployment.yaml`
- Add init container to run migrations
- Test with one service first

### Step 3: Task 4.3 - Update Handlers (8-12 hours)
- Start with one service (e.g., `auth`) as reference
- Implement CRUD operations
- Test thoroughly
- Then replicate pattern to other services

### Step 4: Build & Deploy (30 min)
```bash
./scripts/05-build-microservices.sh
./scripts/06-deploy-microservices.sh --local
```

### Step 5: Testing (5-7 hours)
- Task 5.3: Test Helm deployment
- Task 8.1: Test database connections
- Task 8.2: Test k6 load testing

---

## ⚠️ Blockers for Task 4.3

**Cannot start Task 4.3 until:**
1. ✅ Task 4.4: PostgreSQL driver added to go.mod
2. ✅ Task 3.3: Init containers created (or manual migration)
3. ✅ Task 5.1: Kubernetes Secrets created
4. ✅ Databases deployed and running

**Why:**
- Without driver: Code won't compile
- Without migrations: Tables don't exist → queries will fail
- Without secrets: Services can't connect to databases
- Without databases: Nothing to connect to

---

## 💡 Recommendation

**Start with these 3 tasks BEFORE Task 4.3:**

1. **Task 4.4** (5 min) - Add PostgreSQL driver
2. **Task 3.3** (2-3 hours) - Create init containers for migrations
3. **Task 5.1** (10 min) - Create Kubernetes Secrets

**Then proceed with Task 4.3** (8-12 hours)

This ensures:
- ✅ Code compiles
- ✅ Database tables exist
- ✅ Services can connect
- ✅ Smooth implementation of Task 4.3

---

## 📊 Progress Summary

| Phase | Task | Status | Priority | Time | Blocker? |
|-------|------|--------|----------|------|----------|
| Prerequisites | 4.4: Add driver | ❌ | HIGH | 5 min | ✅ YES |
| Prerequisites | 3.3: Init containers | ❌ | HIGH | 2-3h | ⚠️ Important |
| Prerequisites | 5.1: Create secrets | ❌ | HIGH | 10 min | ✅ YES |
| Infrastructure | Deploy databases | ❌ | HIGH | 15 min | ✅ YES |
| **Implementation** | **4.3: Update handlers** | **❌** | **HIGH** | **8-12h** | **⏳ Waiting** |
| Testing | 5.3: Test deployment | ❌ | MEDIUM | 1-2h | ⏳ After 4.3 |
| Testing | 8.1: Test connections | ❌ | MEDIUM | 2-3h | ⏳ After 4.3 |
| Testing | 8.2: Test k6 | ❌ | MEDIUM | 3-4h | ⏳ After 4.3 |

---

**Next Action**: Complete prerequisites (4.4, 3.3, 5.1) before starting Task 4.3.
