# Implementation Tasks: Frontend Integration Optimization & Production-Ready Deployment

**Task ID:** frontend-integration-optimization
**Created:** 2026-01-08
**Status:** Ready for Implementation
**Based on:** plan.md

---

## Summary

| Metric | Value |
|--------|-------|
| Total Tasks | 7 |
| Estimated Effort | 9-14 hours (1.5-2 days) |
| Phases | 5 |
| Critical Path | Phase 1 → Phase 4 → Phase 5 |

---

## Phase 1: Remove Mock Data (FR-1)

**Goal:** Completely remove all mock data code from frontend, enforce real API usage
**Estimated:** 3-4 hours
**Dependencies:** None

### Task 1.1: Remove Mock Data Files and Logic

**Description:** Delete mock data file and remove all `USE_MOCK` conditional logic from API modules

**Acceptance Criteria:**
- [ ] `frontend/src/api/mockData.js` file deleted
- [ ] All imports of `mockData.js` removed from `frontend/src/api/productApi.js`
- [ ] `USE_MOCK` flag and auto-detection logic removed from `frontend/src/api/config.js`
- [ ] `USE_MOCK` conditional logic removed from `frontend/src/api/productApi.js` (3 functions: `getProducts`, `getProduct`, `getProductDetails`)
- [ ] `USE_MOCK` conditional logic removed from `frontend/src/api/cartApi.js` (5 functions: `getCart`, `getCartCount`, `addToCart`, `updateCartItem`, `removeCartItem`)
- [ ] All console.log statements referencing mock mode removed
- [ ] Verification: `grep -r "USE_MOCK\|mockData\|MOCK_" frontend/src` returns no results

**Effort:** 2 hours
**Priority:** High
**Dependencies:** None
**Assignee:** Unassigned

**Files to modify:**
- `frontend/src/api/mockData.js` - DELETE
- `frontend/src/api/config.js` - Remove USE_MOCK logic
- `frontend/src/api/productApi.js` - Remove mock conditionals
- `frontend/src/api/cartApi.js` - Remove mock conditionals

---

### Task 1.2: Enforce API URL Requirement and Test

**Description:** Update `getApiBaseUrl()` to require `VITE_API_BASE_URL` and verify build behavior

**Acceptance Criteria:**
- [ ] `getApiBaseUrl()` throws clear error if `VITE_API_BASE_URL` is not set
- [ ] Error message: "VITE_API_BASE_URL is required for production build"
- [ ] Build fails without `VITE_API_BASE_URL` set (test: `npm run build` without env var)
- [ ] Build succeeds with `VITE_API_BASE_URL=http://localhost:8080` (test: `VITE_API_BASE_URL=http://localhost:8080 npm run build`)
- [ ] Frontend makes real API calls (no mock path exists)
- [ ] Docker build validates API_BASE_URL requirement (existing Dockerfile check works)

**Effort:** 1-2 hours
**Priority:** High
**Dependencies:** Task 1.1
**Assignee:** Unassigned

**Files to modify:**
- `frontend/src/api/config.js` - Update `getApiBaseUrl()` function

**Test commands:**
```bash
# Test build failure
cd frontend && npm run build
# Expected: Error about VITE_API_BASE_URL

# Test build success
cd frontend && VITE_API_BASE_URL=http://localhost:8080 npm run build
# Expected: Build succeeds, dist/ folder created

# Verify no mock references
grep -r "USE_MOCK\|mockData\|MOCK_" frontend/src
# Expected: No results
```

---

## Phase 2: Enable Seed Data (FR-2)

**Goal:** Rename seed data file to enable automatic Flyway execution
**Estimated:** 1-2 hours
**Dependencies:** None (can run in parallel with Phase 1)

### Task 2.1: Rename Seed File and Verify Migration

**Description:** Rename seed file to match Flyway pattern and verify automatic execution

**Acceptance Criteria:**
- [ ] `services/migrations/product/sql/seed_products.sql` renamed to `V2__seed_products.sql`
- [ ] File follows Flyway versioning pattern: `V{version}__{description}.sql`
- [ ] Verify `ON CONFLICT (name) DO NOTHING` is present (idempotent)
- [ ] Test: Deploy product service and verify seed data loads automatically
- [ ] Verify: `SELECT COUNT(*) FROM products;` returns 8
- [ ] Verify: `SELECT SUM(stock_quantity) FROM products;` returns 233
- [ ] Test: Restart product pod, verify seed data NOT re-run (Flyway skips already-executed migration)
- [ ] Verify: Flyway `schema_version` table shows V2 migration executed

**Effort:** 1-2 hours
**Priority:** High
**Dependencies:** None
**Assignee:** Unassigned

**Files to modify:**
- `services/migrations/product/sql/seed_products.sql` → Rename to `V2__seed_products.sql`

**Verification commands:**
```bash
# Verify file renamed
ls services/migrations/product/sql/V2__seed_products.sql
# Expected: File exists

# Deploy and verify seed data
helm upgrade --install product charts/mop -f charts/mop/values/product.yaml -n product

# Check products loaded
kubectl exec -n product -it <product-pod> -- psql -U product -d product -c "SELECT COUNT(*) FROM products;"
# Expected: 8

kubectl exec -n product -it <product-pod> -- psql -U product -d product -c "SELECT SUM(stock_quantity) FROM products;"
# Expected: 233

# Verify Flyway tracked migration
kubectl exec -n product -it <product-pod> -- psql -U product -d product -c "SELECT version, description FROM schema_version WHERE version = '2';"
# Expected: V2__seed_products.sql recorded
```

---

## Phase 3: Optimize GitHub Actions (FR-3)

**Goal:** Remove redundant build job to reduce CI/CD build time
**Estimated:** 1-2 hours
**Dependencies:** None (can run in parallel with Phase 1)

### Task 3.1: Remove Redundant Build Job

**Description:** Remove standalone `build` job and make `docker` job depend on `lint` directly

**Acceptance Criteria:**
- [ ] `build` job removed from `.github/workflows/build-frontend.yml`
- [ ] `docker` job updated: `needs: build` → `needs: lint`
- [ ] Verify Docker build still validates output (existing `ls -la /app/dist` in Dockerfile)
- [ ] Test: Workflow runs successfully (lint → docker)
- [ ] Measure: Build time reduction (should be ≥ 2 minutes)
- [ ] Test: PR validation still works (Docker build runs for PRs without pushing)
- [ ] Verify: All functionality preserved (lint, build validation, Docker image creation)

**Effort:** 1-2 hours
**Priority:** Medium
**Dependencies:** None
**Assignee:** Unassigned

**Files to modify:**
- `.github/workflows/build-frontend.yml` - Remove build job, update docker job dependency

**Verification:**
- Workflow has 2 jobs: `lint` → `docker`
- Build time reduced by ≥ 2 minutes (compare before/after)
- PR workflow still validates Docker build

---

## Phase 4: Create Helm Values & Deployment (FR-4)

**Goal:** Create Helm values file and enable standardized frontend deployment
**Estimated:** 2-3 hours
**Dependencies:** Task 1.1 (mock data removed, frontend build works)

### Task 4.1: Create Helm Values File

**Description:** Create `charts/mop/values/frontend.yaml` following microservice pattern

**Acceptance Criteria:**
- [ ] `charts/mop/values/frontend.yaml` file created
- [ ] Values file follows same structure as other service values (e.g., `product.yaml`)
- [ ] Configuration includes:
  - `name: frontend`
  - `replicaCount: 1`
  - `image.repository: ghcr.io/duynhne/frontend`
  - `image.tag: v5`
  - `service.type: ClusterIP`
  - `service.port: 80`
  - `containerPort: 80`
  - `livenessProbe` configured for `/health` endpoint (port 80)
  - `readinessProbe` configured for `/health` endpoint (port 80)
  - `resources.requests`: memory "32Mi", cpu "25m"
  - `resources.limits`: memory "64Mi", cpu "50m"
  - `migrations.enabled: false`
- [ ] Test: `helm template frontend charts/mop -f charts/mop/values/frontend.yaml` renders valid Kubernetes manifests
- [ ] Verify: Deployment, Service, and probes configured correctly

**Effort:** 1-2 hours
**Priority:** High
**Dependencies:** Task 1.1
**Assignee:** Unassigned

**Files to create:**
- `charts/mop/values/frontend.yaml`

**Verification:**
```bash
# Validate Helm template
helm template frontend charts/mop -f charts/mop/values/frontend.yaml -n default

# Check rendered manifests
helm template frontend charts/mop -f charts/mop/values/frontend.yaml -n default | grep -A 5 "replicas:"
# Expected: replicas: 1

helm template frontend charts/mop -f charts/mop/values/frontend.yaml -n default | grep -A 3 "livenessProbe:"
# Expected: path: /health, port: 80
```

---

### Task 4.2: Deploy and Configure Port-Forward

**Description:** Deploy frontend via Helm and add port-forward to access script

**Acceptance Criteria:**
- [ ] Frontend deployed via Helm: `helm install frontend charts/mop -f charts/mop/values/frontend.yaml -n default`
- [ ] Verify: Pod starts successfully
- [ ] Verify: Health checks pass (`/health` endpoint responds)
- [ ] Add frontend port-forward to `scripts/08-setup-access.sh`
- [ ] Port-forward command: `kubectl port-forward -n default svc/frontend 3000:80`
- [ ] Test: Frontend accessible at `http://localhost:3000`
- [ ] Test: Health check accessible at `http://localhost:3000/health` (returns "healthy")
- [ ] Update access script output to include frontend URL

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 4.1
**Assignee:** Unassigned

**Files to modify:**
- `scripts/08-setup-access.sh` - Add frontend port-forward

**Verification:**
```bash
# Deploy frontend
helm install frontend charts/mop -f charts/mop/values/frontend.yaml -n default

# Check pod status
kubectl get pods -n default -l app=frontend
# Expected: Pod Running

# Test health check
kubectl exec -n default <frontend-pod> -- wget -qO- http://localhost/health
# Expected: "healthy"

# Test port-forward (after adding to script)
kubectl port-forward -n default svc/frontend 3000:80 &
curl http://localhost:3000/health
# Expected: "healthy"
```

---

## Phase 5: Document API Mapping (FR-5)

**Goal:** Add comprehensive API endpoint mapping and localhost explanation to README
**Estimated:** 2-3 hours
**Dependencies:** Task 1.1 (code changes complete)

### Task 5.1: Add API Documentation to README

**Description:** Add API endpoint mapping table and localhost:8080 explanation to frontend README

**Acceptance Criteria:**
- [ ] API endpoint mapping table added to `frontend/README.md`
- [ ] Table includes columns:
  - Frontend API endpoint
  - HTTP Method
  - Backend Service
  - Backend Handler function
  - Web Layer file location
  - Logic Layer call
- [ ] All 13 endpoints documented:
  - Product: 3 endpoints (GET /products, GET /products/:id, GET /products/:id/details)
  - Cart: 5 endpoints (GET /cart, GET /cart/count, POST /cart, PATCH /cart/items/:id, DELETE /cart/items/:id)
  - Order: 3 endpoints (GET /orders, GET /orders/:id, POST /orders)
  - Auth: 2 endpoints (POST /auth/login, POST /auth/register)
- [ ] Aggregation endpoints marked with ⭐ symbol
- [ ] Request flow diagram included (Frontend → Web Layer → Logic Layer → Core Layer)
- [ ] Add "Frontend-Backend Integration" section with localhost:8080 explanation (as requested)
- [ ] Document port-forward procedure
- [ ] Update deployment instructions to include Helm deployment
- [ ] Table references actual file paths and line numbers where possible

**Effort:** 2-3 hours
**Priority:** Medium
**Dependencies:** Task 1.1
**Assignee:** Unassigned

**Files to modify:**
- `frontend/README.md` - Add API mapping section

**Documentation section to add:**
```markdown
## Frontend-Backend Integration

### API URL Configuration: localhost:8080 for Local/Kind Testing

**Important:** Frontend runs in the browser, not in the Kubernetes pod.

**How it works:**
1. **Frontend pod** serves static files via nginx (port 80)
2. **Browser** loads frontend from `localhost:3000` (port-forwarded from pod)
3. **Browser** makes API calls to `localhost:8080` (backend services port-forwarded)
4. **`localhost` in browser** = user's machine, NOT pod's localhost
5. **Port-forward** bridges browser → Kubernetes services

**Why `localhost:8080` works:**
- Frontend code runs in **browser JavaScript** (not in pod)
- Browser's `localhost` refers to **user's machine**
- Backend services port-forwarded to `localhost:8080` on user's machine
- Frontend API calls from browser → `localhost:8080` → port-forward → backend service ✅

**For Production (Real K8s):**
- Would use service DNS: `http://product.default.svc.cluster.local:8080`
- But for Kind/local testing: `localhost:8080` is correct ✅

**Setup:**
```bash
# Port-forward backend services (via scripts/08-setup-access.sh)
kubectl port-forward -n product svc/product 8080:8080

# Frontend build with localhost:8080
docker build --build-arg API_BASE_URL=http://localhost:8080 -t frontend .

# Frontend in browser calls: http://localhost:8080/api/v1/products
```

### API Endpoint Mapping

[Table with all 13 endpoints mapped to backend handlers]
```

**Verification:**
- API mapping table present in README
- All 13 endpoints documented
- localhost:8080 explanation included
- Port-forward procedure documented
- Request flow diagram included

---

## Dependency Graph

```
Phase 1: Remove Mock Data
├── Task 1.1: Remove Mock Data Files and Logic
│   └── Task 1.2: Enforce API URL Requirement and Test

Phase 2: Enable Seed Data (parallel with Phase 1)
└── Task 2.1: Rename Seed File and Verify Migration

Phase 3: Optimize GitHub Actions (parallel with Phase 1)
└── Task 3.1: Remove Redundant Build Job

Phase 4: Create Helm Values (depends on Phase 1)
├── Task 4.1: Create Helm Values File (depends on Task 1.1)
│   └── Task 4.2: Deploy and Configure Port-Forward (depends on Task 4.1)

Phase 5: Document API Mapping (depends on Phase 1)
└── Task 5.1: Add API Documentation to README (depends on Task 1.1)
```

---

## Quick Reference Checklist

### Phase 1: Remove Mock Data (3-4 hours)
- [ ] Task 1.1: Remove Mock Data Files and Logic (2h)
- [ ] Task 1.2: Enforce API URL Requirement and Test (1-2h)

### Phase 2: Enable Seed Data (1-2 hours)
- [ ] Task 2.1: Rename Seed File and Verify Migration (1-2h)

### Phase 3: Optimize GitHub Actions (1-2 hours)
- [ ] Task 3.1: Remove Redundant Build Job (1-2h)

### Phase 4: Create Helm Values & Deployment (2-3 hours)
- [ ] Task 4.1: Create Helm Values File (1-2h)
- [ ] Task 4.2: Deploy and Configure Port-Forward (1h)

### Phase 5: Document API Mapping (2-3 hours)
- [ ] Task 5.1: Add API Documentation to README (2-3h)

---

## Risk Areas

| Task | Risk | Mitigation |
|------|------|------------|
| Task 1.2 | Build fails without clear error message | Test error message clarity, update if needed |
| Task 2.1 | Seed data doesn't load | Verify Flyway migration logs, check schema_version table |
| Task 3.1 | GitHub Actions workflow breaks | Test workflow thoroughly, can revert if needed |
| Task 4.1 | Helm values misconfigured | Use `helm template` to validate before deployment |
| Task 4.2 | Port-forward conflicts with existing | Check port 3000 availability, use different port if needed |
| Task 5.1 | Documentation becomes outdated | Keep documentation as reference, code is source of truth |

---

## Implementation Order

**Recommended execution order:**

1. **Start with Phase 1** (foundational - removes mock data)
   - Task 1.1 → Task 1.2

2. **Run Phase 2 and Phase 3 in parallel** (independent, can run simultaneously)
   - Task 2.1 (seed data)
   - Task 3.1 (GitHub Actions)

3. **After Phase 1 complete, run Phase 4** (needs mock data removed)
   - Task 4.1 → Task 4.2

4. **After Phase 1 complete, run Phase 5** (needs code changes complete)
   - Task 5.1

**Critical path:** Phase 1 → Phase 4 → Phase 5 (sequential)
**Parallel opportunities:** Phase 2 and Phase 3 can run anytime

---

## Verification Commands

### After Phase 1 (Mock Data Removal)
```bash
# Verify no mock references
grep -r "USE_MOCK\|mockData\|MOCK_" frontend/src
# Expected: No results

# Test build failure
cd frontend && npm run build
# Expected: Error about VITE_API_BASE_URL

# Test build success
cd frontend && VITE_API_BASE_URL=http://localhost:8080 npm run build
# Expected: Build succeeds
```

### After Phase 2 (Seed Data)
```bash
# Verify seed data loaded
kubectl exec -n product -it <product-pod> -- psql -U product -d product -c "SELECT COUNT(*) FROM products;"
# Expected: 8

kubectl exec -n product -it <product-pod> -- psql -U product -d product -c "SELECT SUM(stock_quantity) FROM products;"
# Expected: 233
```

### After Phase 3 (GitHub Actions)
```bash
# Check workflow file
cat .github/workflows/build-frontend.yml | grep -A 2 "jobs:"
# Expected: Only lint and docker jobs

# Measure build time (compare before/after)
# Expected: ≥ 2 minutes reduction
```

### After Phase 4 (Helm Deployment)
```bash
# Validate Helm template
helm template frontend charts/mop -f charts/mop/values/frontend.yaml -n default
# Expected: Valid Kubernetes manifests

# Test deployment
helm install frontend charts/mop -f charts/mop/values/frontend.yaml -n default
# Expected: Deployment successful

# Test port-forward
kubectl port-forward -n default svc/frontend 3000:80 &
curl http://localhost:3000/health
# Expected: "healthy"
```

### After Phase 5 (Documentation)
```bash
# Verify documentation exists
grep -A 10 "Frontend-Backend Integration" frontend/README.md
# Expected: Section found with localhost:8080 explanation

grep -c "GET\|POST\|PATCH\|DELETE" frontend/README.md
# Expected: At least 13 endpoint references
```

---

## Next Steps

1. ✅ Review task breakdown
2. Assign tasks to developers (or proceed solo)
3. Run `/implement frontend-integration-optimization` to start execution
4. Begin with Phase 1, Task 1.1 (Remove Mock Data Files and Logic)
5. Test each task before moving to next
6. Update checklist as tasks complete

---

*Tasks created with SDD 2.0*
