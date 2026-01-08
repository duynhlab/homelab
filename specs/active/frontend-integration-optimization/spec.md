# Specification: Frontend Integration Optimization & Production-Ready Deployment

**Task ID:** frontend-integration-optimization
**Created:** 2026-01-08
**Status:** Ready for Planning
**Version:** 1.0

---

## 1. Problem Statement

### The Problem

The newly integrated React frontend has several issues preventing production-ready deployment:

1. **Mock data in production code**: Frontend contains mock data that should be removed for production deployment. Mock data exists in `mockData.js` and is used via `USE_MOCK` flag in API modules, creating maintenance burden and potential confusion.

2. **Seed data not automatically loaded**: Product seed data exists in `seed_products.sql` but is not automatically executed by Flyway migrations because it doesn't match the required naming pattern (`V*__*.sql`).

3. **Inefficient CI/CD pipeline**: GitHub Actions workflow has redundant `build` job that duplicates work already done in Docker build stage, wasting ~2-3 minutes per build.

4. **Missing Helm deployment config**: Frontend service lacks Helm values file for Kubernetes deployment, preventing standardized deployment alongside other microservices.

5. **Incomplete API documentation**: Frontend API endpoint mapping to backend 3-layer architecture is not documented, making it difficult to understand integration points.

### Current Situation

- Frontend uses mock data when `VITE_API_BASE_URL` is not set (auto-detection)
- Seed data file exists but requires manual execution
- GitHub Actions runs `npm run build` twice (once in build job, once in Docker)
- Frontend deployment requires manual Kubernetes manifests
- API integration points are scattered across codebase without clear documentation

### Desired Outcome

- **Production-ready frontend**: No mock data code, always uses real API
- **Automatic seed data**: Product catalog automatically loaded on deployment via Flyway
- **Optimized CI/CD**: Faster builds with no redundant steps
- **Standardized deployment**: Frontend deployable via Helm like other microservices
- **Clear documentation**: API endpoint mapping table in frontend README

---

## 2. User Personas

### Primary User: DevOps/SRE Engineer

- **Who:** Team member responsible for deploying and maintaining the e-commerce platform
- **Goals:** 
  - Deploy frontend to production with minimal configuration
  - Ensure frontend uses real backend APIs (no mock data)
  - Have product catalog automatically available after deployment
  - Use consistent deployment patterns across all services
- **Pain points:** 
  - Manual seed data execution is easy to forget
  - Inconsistent deployment methods (Helm for services, manual for frontend)
  - Slow CI/CD builds waste time
- **Tech comfort:** High - comfortable with Kubernetes, Helm, CI/CD pipelines

### Secondary User: Frontend Developer

- **Who:** Developer working on React frontend application
- **Goals:**
  - Understand how frontend integrates with backend APIs
  - Test frontend locally with real backend
  - Have clear documentation of API contracts
- **Pain points:**
  - Unclear which backend endpoints frontend uses
  - Mock data creates confusion about real API behavior
  - No clear documentation of API integration points
- **Tech comfort:** Medium-High - comfortable with React, needs clear API documentation

---

## 3. Functional Requirements

### FR-1: Remove Mock Data from Frontend

**Description:** Completely remove all mock data code from frontend codebase to ensure production-ready deployment that always uses real backend APIs.

**User Story:**
> As a DevOps engineer, I want the frontend to have no mock data code so that production deployments always use real APIs and there's no confusion about data sources.

**Acceptance Criteria:**
- [ ] `frontend/src/api/mockData.js` file is deleted
- [ ] All imports of `mockData.js` removed from `productApi.js`
- [ ] `USE_MOCK` flag logic removed from `frontend/src/api/config.js`
- [ ] `USE_MOCK` conditional logic removed from `frontend/src/api/productApi.js` (3 functions: `getProducts`, `getProduct`, `getProductDetails`)
- [ ] `USE_MOCK` conditional logic removed from `frontend/src/api/cartApi.js` (empty mock responses)
- [ ] Frontend build fails if `VITE_API_BASE_URL` is not set (no fallback to mock)
- [ ] All console.log statements referencing mock mode are removed
- [ ] Frontend always makes HTTP requests to real API (no mock path)

**Priority:** Must Have

**Technical Notes:**
- Remove `USE_MOCK` auto-detection logic
- Make `VITE_API_BASE_URL` required in build (throw error if missing)
- Update `getApiBaseUrl()` to always return real API URL
- For local/Kind testing: Use `API_BASE_URL=http://localhost:8080` in Docker build
- Frontend runs in browser (not in pod), so `localhost:8080` correctly points to port-forwarded backend

---

### FR-2: Enable Automatic Seed Data via Flyway Migration

**Description:** Rename seed data file to match Flyway naming pattern so it executes automatically during database migrations, ensuring product catalog is available after deployment.

**User Story:**
> As a DevOps engineer, I want product seed data to load automatically during deployment so that the product catalog is immediately available without manual intervention.

**Acceptance Criteria:**
- [ ] `services/migrations/product/sql/seed_products.sql` renamed to `V2__seed_products.sql`
- [ ] Seed file follows Flyway versioning pattern (`V{version}__{description}.sql`)
- [ ] Seed data executes automatically after `V1__init_schema.sql` during Flyway migration
- [ ] Seed data is idempotent (uses `ON CONFLICT DO NOTHING` for safety)
- [ ] After migration, database contains 8 products with expected data
- [ ] Verification query confirms: `product_count = 8`, `total_stock = 233`
- [ ] Seed data runs **once per database** (Flyway tracks in `schema_version` table)
- [ ] Pod restarts do NOT re-run seed data (Flyway skips already-executed migrations)

**Priority:** Must Have

**Technical Notes:**
- Flyway executes files in version order: V1 → V2 → V3...
- Current file `seed_products.sql` is ignored (doesn't match pattern)
- Rename to `V2__seed_products.sql` to execute after schema creation
- Dockerfile already copies `sql/` folder, so file will be included automatically

---

### FR-3: Optimize GitHub Actions Workflow

**Description:** Remove redundant `build` job from GitHub Actions workflow since Docker build already performs the same build steps, reducing build time by ~2-3 minutes.

**User Story:**
> As a DevOps engineer, I want the CI/CD pipeline to be efficient so that builds complete faster and we don't waste time on redundant steps.

**Acceptance Criteria:**
- [ ] `build` job removed from `.github/workflows/build-frontend.yml`
- [ ] `docker` job depends on `lint` job (instead of `build`)
- [ ] Docker build still validates build output (existing `ls -la /app/dist` in Dockerfile)
- [ ] Build time reduced by at least 2 minutes
- [ ] All existing functionality preserved (lint, build, Docker image creation)
- [ ] PR validation still works (Docker build runs for PRs without pushing)

**Priority:** Must Have

**Technical Notes:**
- Current workflow: `lint` → `build` → `docker`
- Optimized workflow: `lint` → `docker`
- Docker build stage already runs: `npm ci`, `npm run build`, `ls -la dist/`
- Build verification happens in Docker build, no separate job needed

---

### FR-4: Create Helm Values for Frontend Deployment

**Description:** Create Helm values file for frontend service following the same pattern as microservices, enabling standardized Kubernetes deployment.

**User Story:**
> As a DevOps engineer, I want to deploy frontend using Helm like other services so that deployment is consistent and maintainable across all services.

**Acceptance Criteria:**
- [ ] `charts/mop/values/frontend.yaml` file created
- [ ] Values file follows same structure as other service values (e.g., `product.yaml`)
- [ ] Configuration includes:
  - `name: frontend`
  - `replicaCount: 1` (static files, no scaling needed)
  - `image.repository: ghcr.io/duynhne/frontend`
  - `image.tag: v5`
  - `service.type: ClusterIP` (for Kind/local testing, use port-forward)
  - `service.port: 80` (nginx default)
  - `containerPort: 80`
  - `livenessProbe` and `readinessProbe` configured for `/health` endpoint (already exists in nginx.conf)
  - `resources` set to minimal (32Mi memory, 25m CPU)
  - `migrations.enabled: false` (no database)
- [ ] Frontend can be deployed via: `helm install frontend charts/mop -f charts/mop/values/frontend.yaml -n default`
- [ ] Deployment uses existing `charts/mop/templates/deployment.yaml` (no template changes needed)
- [ ] Port-forward added to `scripts/08-setup-access.sh` for local access: `kubectl port-forward -n default svc/frontend 3000:80`

**Priority:** Must Have

**Technical Notes:**
- Frontend is static files served by nginx (different from Go microservices)
- No database, no migrations, no environment variables needed
- Health check uses nginx `/health` endpoint
- Single replica sufficient (static files don't need scaling)

---

### FR-5: Document API Endpoint Mapping

**Description:** Add comprehensive API endpoint mapping table to frontend README documenting how frontend APIs map to backend 3-layer architecture.

**User Story:**
> As a frontend developer, I want clear documentation of which backend endpoints the frontend uses so that I can understand the integration and debug issues more easily.

**Acceptance Criteria:**
- [ ] API endpoint mapping table added to `frontend/README.md`
- [ ] Table includes columns:
  - Frontend API endpoint
  - HTTP Method
  - Backend Service
  - Backend Handler function
  - Web Layer file location
  - Logic Layer call
- [ ] All 13 frontend endpoints documented:
  - Product: 3 endpoints (GET /products, GET /products/:id, GET /products/:id/details)
  - Cart: 5 endpoints (GET /cart, GET /cart/count, POST /cart, PATCH /cart/items/:id, DELETE /cart/items/:id)
  - Order: 3 endpoints (GET /orders, GET /orders/:id, POST /orders)
  - Auth: 2 endpoints (POST /auth/login, POST /auth/register)
- [ ] Aggregation endpoints marked with ⭐ symbol
- [ ] Request flow diagram included (Frontend → Web Layer → Logic Layer → Core Layer)
- [ ] Table references actual file paths and line numbers where possible

**Priority:** Should Have

**Technical Notes:**
- Mapping table already created in research document
- Can be copied/adapted to README format
- Helps developers understand 3-layer architecture integration

---

## 4. Non-Functional Requirements

### NFR-1: Build Performance

- **Requirement:** Frontend build time should be reduced by at least 2 minutes
- **Measurement:** Compare build time before/after GitHub Actions optimization
- **Target:** Build completes in < 5 minutes (down from ~7 minutes)

### NFR-2: Deployment Consistency

- **Requirement:** Frontend deployment should follow same Helm pattern as microservices
- **Measurement:** Frontend can be deployed using same Helm commands as other services
- **Target:** 100% consistency with microservice deployment pattern

### NFR-3: Production Readiness

- **Requirement:** Frontend should have zero mock data code in production builds
- **Measurement:** No references to `mockData`, `USE_MOCK`, or mock mode in production bundle
- **Target:** 0 mock-related code in production build

### NFR-4: Seed Data Reliability

- **Requirement:** Seed data should load automatically and reliably on every deployment
- **Measurement:** Product count = 8 after migration completes
- **Target:** 100% success rate for seed data loading

### NFR-5: Documentation Completeness

- **Requirement:** All frontend API endpoints should be documented with backend mapping
- **Measurement:** 13/13 endpoints documented in README
- **Target:** 100% endpoint coverage

### NFR-6: Code Maintainability

- **Requirement:** Removed mock data code should not break existing functionality
- **Measurement:** All frontend API calls work with real backend
- **Target:** Zero regression in API integration

---

## 5. Out of Scope

The following are explicitly NOT included in this feature:

- ❌ **Runtime API URL configuration** - Frontend uses build-time configuration only (no runtime injection)
- ❌ **Multiple environment support** - Single production deployment pattern (dev/staging handled separately)
- ❌ **Frontend service scaling** - Single replica sufficient (static files, no need for HPA)
- ❌ **Mock data for other services** - Only Product API mock data removed (Cart/Order/Auth don't have mock data)
- ❌ **API versioning changes** - Frontend continues using `/api/v1` (no v2 migration)
- ❌ **Frontend template changes** - Only values file created (no Helm template modifications)
- ❌ **Development workflow automation** - Local testing workflow documented but not automated
- ❌ **Seed data for other services** - Only Product service seed data enabled (other services may have seed data later)

---

## 6. Edge Cases & Error Handling

### Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| `VITE_API_BASE_URL` not set during build | Build fails with clear error message: "VITE_API_BASE_URL required for production build" |
| Seed data file already exists in database | Flyway migration succeeds, `ON CONFLICT DO NOTHING` prevents duplicates |
| Frontend deployed before backend is ready | Frontend shows API errors, retries automatically via axios interceptor |
| Seed data migration fails | Deployment fails, init container error visible in pod logs |
| GitHub Actions lint job fails | Docker job does not run (dependency chain broken) |
| Helm values file has incorrect port | Deployment succeeds but health checks fail (Kubernetes will mark pod unhealthy) |
| API endpoint mapping documentation outdated | Developers refer to codebase directly (documentation is reference, not source of truth) |

### Error Scenarios

| Error | User Message | System Action |
|-------|--------------|---------------|
| Build fails: API_BASE_URL missing | "ERROR: VITE_API_BASE_URL not set but mock mode is disabled" | Build fails, Docker image not created |
| Seed data migration fails | Flyway error in init container logs | Pod fails to start, deployment blocked |
| Frontend can't connect to backend | API calls return 500/503 errors | Frontend shows error message, user can retry |
| Health check fails | Kubernetes marks pod unhealthy | Pod restarted, eventually evicted if continues failing |
| Helm deployment fails | Helm error message | Deployment rolled back, previous version remains |

### Rollback Scenarios

| Scenario | Rollback Strategy |
|----------|-------------------|
| Frontend deployment breaks | Helm rollback: `helm rollback frontend` |
| Seed data causes issues | Manual SQL: `DELETE FROM products WHERE id IN (...)` |
| GitHub Actions optimization breaks builds | Revert workflow file to previous version |
| Mock data removal breaks local dev | Developers use port-forward: `kubectl port-forward svc/product 8080:8080` |

---

## 7. Success Metrics

### Key Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Build time reduction | ≥ 2 minutes | Compare GitHub Actions build duration before/after |
| Mock data removal | 0 files | Count files containing "mockData" or "USE_MOCK" in frontend codebase |
| Seed data success rate | 100% | Verify product count = 8 after each deployment |
| Deployment consistency | 100% | Frontend deployable via Helm like other services |
| API documentation coverage | 13/13 endpoints | Count documented endpoints in README |
| Production build success | 100% | All production builds succeed with API_BASE_URL set |

### Definition of Done

- [ ] All acceptance criteria met for FR-1 through FR-5
- [ ] Mock data completely removed (0 references in codebase)
- [ ] Seed data automatically loads on deployment (verified in test deployment)
- [ ] GitHub Actions build time reduced by ≥ 2 minutes
- [ ] Helm values file created and tested (frontend deployable via Helm)
- [ ] API endpoint mapping table added to frontend README
- [ ] All edge cases handled (error messages clear, rollback procedures documented)
- [ ] Performance targets achieved (build time, deployment consistency)
- [ ] Documentation updated (README, deployment guides if needed)

---

## 8. Open Questions - RESOLVED

- [x] **Production API URL**: What is the actual production API base URL? (Currently using placeholder `https://api.production.com` in Docker builds)
  - **Decision:** **`http://localhost:8080`** for local/Kind testing
  - **Rationale:** 
    - Frontend runs in browser (not in pod), so `localhost` refers to user's machine
    - Backend services are port-forwarded to `localhost:8080` (via `scripts/08-setup-access.sh`)
    - Frontend in browser can call `http://localhost:8080/api/v1` successfully
  - **Docker build:** Use `API_BASE_URL=http://localhost:8080` for local testing builds
  - **Note:** For production (real K8s), would use service name like `http://product.default.svc.cluster.local:8080`, but for Kind/local testing, `localhost:8080` is correct
  
- [x] **Frontend namespace**: Should frontend deploy to `default` namespace or create dedicated `frontend` namespace?
  - **Decision:** **`default` namespace** - Keep it simple, consistent with Kind/local testing setup
  
- [x] **Service type**: Should frontend service be `ClusterIP` (internal) or `LoadBalancer`/`Ingress` (external access)?
  - **Decision:** **`ClusterIP`** - Use port-forward for local access (Kind doesn't support LoadBalancer)
  - **Solution:** Add frontend port-forward to `scripts/08-setup-access.sh` following existing pattern
  - **Access:** `kubectl port-forward -n default svc/frontend 3000:80` (or similar)
  - **Backend API access:** Frontend uses `http://localhost:8080` (backend port-forwarded via same script)
  - **Note:** Frontend runs in browser, so `localhost` refers to user's machine, not pod
  
- [x] **Health check endpoint**: Does `nginx.conf` already have `/health` endpoint configured, or does it need to be added?
  - **Status:** **Already configured** - `nginx.conf` has `/health` endpoint (lines 20-25)
  - **Decision:** Use existing `/health` endpoint, no changes needed
  
- [x] **Development workflow**: After removing mock data, should we document port-forward procedure or provide local backend setup guide?
  - **Decision:** Document port-forward procedure in `frontend/README.md`
  - **Pattern:** Follow same approach as `scripts/08-setup-access.sh` for consistency
  
- [x] **Seed data timing**: Confirm seed data should run on every deployment (idempotent) - this is assumed based on `ON CONFLICT DO NOTHING`
  - **Clarification:** Flyway tracks executed migrations in `schema_version` table
  - **Behavior:** `V2__seed_products.sql` runs **only on first deployment** (when V2 migration is new)
  - **Restart pods:** Does NOT re-run seed data - Flyway sees V2 already executed, skips it
  - **Best practice:** ✅ Correct - Seed data runs once, `ON CONFLICT DO NOTHING` is safety net for manual re-runs
  - **Decision:** Keep idempotent design (`ON CONFLICT DO NOTHING`) but understand Flyway only runs new migrations

**Summary of Decisions:**
- Namespace: `default`
- Service type: `ClusterIP` + port-forward (add to `08-setup-access.sh`)
- Health check: Use existing `/health` in nginx.conf
- Seed data: Runs once per database (Flyway tracks), idempotent for safety

---

## 9. Dependencies

### Prerequisites

- [ ] Backend services deployed and accessible (Product, Cart, Order, Auth services)
- [ ] Database migrations working (Flyway init containers functional)
- [ ] Helm chart `charts/mop` exists and supports frontend configuration
- [ ] GitHub Actions has access to container registry (ghcr.io)
- [ ] Kubernetes cluster available for testing deployment

### Blocking Dependencies

- None - All requirements can be implemented independently

### Optional Enhancements

- Frontend monitoring/metrics (can be added later)
- Frontend SLO configuration (can use existing Sloth operator pattern)
- Multi-environment Helm values (dev/staging/prod) - out of scope for v1

---

## 10. Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.1 | 2026-01-08 | Resolved open questions: namespace=default, service=ClusterIP+port-forward, health check exists, seed data runs once | AI Agent |
| 1.0 | 2026-01-08 | Initial specification based on research findings | AI Agent |

---

## Next Steps

1. ✅ Review spec with stakeholders (research findings already reviewed)
2. ✅ Resolve open questions (6 items - all resolved)
3. Run `/plan frontend-integration-optimization` to create technical implementation plan
4. Run `/tasks frontend-integration-optimization` to break down into executable tasks
5. Begin implementation starting with FR-1 (mock data removal) as it's foundational

---

*Specification created with SDD 2.0*
