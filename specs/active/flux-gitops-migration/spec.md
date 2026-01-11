# Specification: Production-Ready GitOps with Flux Operator + Kustomize

**Task ID:** flux-gitops-migration
**Created:** 2026-01-10
**Status:** Ready for Planning
**Version:** 1.0

---

## 1. Problem Statement

### The Problem

Current deployment system relies on **manual script-based execution** with significant pain points:

1. **Manual Sequential Execution**: Must run 8 bash scripts in correct order (01-08), prone to human error
2. **No Drift Detection**: Manual `kubectl` changes are not tracked or auto-corrected
3. **Configuration Duplication**: 11 Helm values files (~900 lines) with 80% duplicated content
4. **No Environment Parity**: Difficult to ensure consistency between local/staging/production
5. **Manual Rollback**: No automated rollback mechanism, requires manual `helm rollback`
6. **No Continuous Sync**: Changes require manual script re-run, no automatic reconciliation

### Current Situation

**Deployment Process:**
```bash
./scripts/01-create-kind-cluster.sh      # Manual execution
./scripts/02-deploy-monitoring.sh        # Manual execution
./scripts/03-deploy-apm.sh               # Manual execution
./scripts/04-deploy-databases.sh         # Manual execution
./scripts/05-deploy-microservices.sh     # Manual execution (9 services)
./scripts/06-deploy-k6.sh                # Manual execution
./scripts/07-deploy-slo.sh               # Manual execution
./scripts/08-setup-access.sh             # Manual port-forwarding
```

**Pain Points:**
- DevOps/SRE must remember correct execution order
- Configuration changes require editing 11 separate Helm values files
- No visibility into what changed or who changed it
- Local development differs from production (no environment parity)
- Deployment takes 30+ minutes manually

### Desired Outcome

**GitOps-based automated deployment** with:
- ✅ **Declarative Configuration**: All infrastructure/apps defined in Git
- ✅ **Automatic Reconciliation**: Flux Operator continuously syncs cluster state
- ✅ **Zero Duplication**: Kustomize base/overlay pattern (900 → 300 lines)
- ✅ **Environment Parity**: Same base manifests for local/staging/production
- ✅ **Drift Detection**: Auto-heal manual changes
- ✅ **Web UI Monitoring**: Flux Web UI for real-time visibility
- ✅ **Deployment Time**: Reduce from 30 min → 5 min

---

## 2. User Personas

### Primary User 1: DevOps/SRE Engineer (You)

- **Who:** Senior DevOps/SRE engineer managing microservices platform
- **Goals:** 
  - Learn production-ready GitOps patterns for career advancement
  - Master Flux Operator + Kustomize for CV/portfolio
  - Automate deployment workflows
  - Reduce operational toil
- **Pain points:** 
  - Manual script execution is time-consuming and error-prone
  - Configuration duplication makes updates tedious
  - Difficult to demonstrate environment parity to management
  - No automated drift detection
- **Tech comfort:** High - comfortable with Kubernetes, Helm, Operators
- **Success criteria:** 
  - Promotion to Senior SRE
  - Salary increase
  - Portfolio project showcasing GitOps expertise

### Primary User 2: Developer

- **Who:** Backend developer working on 9 microservices (auth, user, product, cart, order, review, notification, shipping)
- **Goals:**
  - Deploy services quickly for testing
  - Test changes locally before production
  - Understand deployment status
- **Pain points:**
  - Must ask DevOps to run scripts for deployments
  - Unclear which environment has which version
  - Manual rollback requires DevOps intervention
- **Tech comfort:** Medium - knows Docker/Kubernetes basics, not expert in operators
- **Success criteria:**
  - Self-service deployments for testing
  - Clear visibility into deployment status

### Secondary User: On-Call Engineer

- **Who:** Engineer on-call rotation for incident response
- **Goals:**
  - Quickly understand system state during incidents
  - Rollback problematic deployments
  - Verify deployment health
- **Pain points:**
  - Must run multiple `kubectl get` commands to understand state
  - Rollback requires manual Helm commands
  - No unified view of all deployments
- **Tech comfort:** Medium-High
- **Success criteria:**
  - Flux Web UI for quick status checks
  - Automated rollback via Git revert

---

## 3. Functional Requirements

### FR-1: Flux Operator Installation & Bootstrap

**Description:** Install Flux Operator on local Kind cluster and configure FluxInstance CRD for continuous GitOps reconciliation.

**User Story:**
> As a DevOps Engineer, I want to install Flux Operator with a single command so that I can bootstrap GitOps on my Kind cluster without manual CLI configuration.

**Acceptance Criteria:**
- [ ] Given Kind cluster is running, when I run `make flux-up`, then Flux Operator is installed in `flux-system` namespace
- [ ] Given Flux Operator is installed, when I check pods, then all Flux controllers are running (source-controller, kustomize-controller, helm-controller, notification-controller)
- [ ] Given FluxInstance is created, when I run `flux-operator -n flux-system tree`, then I see the Flux component tree
- [ ] Given Flux is bootstrapped, when manifests change in OCI registry, then Flux automatically reconciles within 10 minutes

**Priority:** Must Have (Phase 1)

---

### FR-2: Kustomize Base/Overlay Repository Structure

**Description:** Create production-ready repository structure with Kustomize base manifests and environment-specific overlays (local/staging/production) to eliminate configuration duplication.

**Architecture Decision (Updated 2026-01-10):**
- **9 backend services:** HelmRelease + Kustomize patches (production-ready, standard pattern)
- **1 frontend service:** ResourceSet + ResourceSetInputProvider (learning Flux Operator advanced features)

**Rationale for Hybrid Approach:**
- Learn both patterns side-by-side
- Frontend is simple (no database, minimal env vars) - ideal for ResourceSet experiment
- Backend services use production-proven HelmRelease + Kustomize pattern
- Can compare patterns and decide on future adoption

**User Story:**
> As a DevOps Engineer, I want to organize Kubernetes manifests using Kustomize base/overlay pattern for backend services and ResourceSet for frontend so that I can maintain a single source of truth while learning Flux Operator advanced patterns.

**Acceptance Criteria:**
- [ ] Given repository structure exists, when I run `tree kubernetes/`, then I see `base/`, `overlays/`, and `clusters/` directories
- [ ] Given base manifests are created (9 HelmReleases + 1 ResourceSet), when I run `kubectl apply -k kubernetes/base/apps/auth`, then auth service deploys with default configuration (2 replicas, 64Mi memory)
- [ ] Given ResourceSet for frontend exists, when I run `kubectl get resourceset frontend`, then frontend deploys via ResourceSet pattern
- [ ] Given local overlay exists, when I run `kubectl apply -k kubernetes/overlays/local/apps`, then all 9 backend services deploy with local configuration (1 replica, 32Mi memory)
- [ ] Given overlay patches exist, when I update a patch file, then only the patched fields change (not entire manifest)
- [ ] Given base is updated, when I run `kubectl apply -k overlays/local`, then changes automatically propagate to overlay

**Priority:** Must Have (Phase 1-2)

**Files Created:**
```
kubernetes/
├── base/
│   ├── infrastructure/     # Monitoring, APM, Databases
│   └── apps/
│       ├── auth/helmrelease.yaml           # HelmRelease (backend)
│       ├── user/helmrelease.yaml           # HelmRelease (backend)
│       ├── product/helmrelease.yaml        # HelmRelease (backend)
│       ├── cart/helmrelease.yaml           # HelmRelease (backend)
│       ├── order/helmrelease.yaml          # HelmRelease (backend)
│       ├── review/helmrelease.yaml         # HelmRelease (backend)
│       ├── notification/helmrelease.yaml   # HelmRelease (backend)
│       ├── shipping/helmrelease.yaml       # HelmRelease (backend)
│       ├── shipping-v2/helmrelease.yaml    # HelmRelease (backend)
│       └── frontend/
│           ├── resourceset.yaml            # ResourceSet (learning)
│           └── inputprovider.yaml          # ResourceSetInputProvider
├── overlays/
│   ├── local/              # 1 replica, minimal resources
│   ├── staging/            # 2 replicas, medium resources (future)
│   └── production/         # 3 replicas, full resources (future)
└── clusters/
    └── local/
        ├── flux-system/
        ├── infrastructure.yaml
        └── apps.yaml
```

---

### FR-3: OCI Artifact Management for Manifests

**Description:** Push Kubernetes manifests as OCI artifacts to local registry (localhost:5050) and configure Flux to pull from OCI registry instead of Git repository.

**User Story:**
> As a DevOps Engineer, I want to store Kubernetes manifests as OCI artifacts so that I can version manifests immutably and sync them faster than Git-based workflows.

**Acceptance Criteria:**
- [ ] Given manifests are ready, when I run `make flux-push`, then manifests are pushed to `localhost:5050/flux-infra-sync:local` and `localhost:5050/flux-apps-sync:local`
- [ ] Given OCI artifacts are pushed, when I run `flux get sources oci`, then I see OCIRepository resources with status "Ready"
- [ ] Given Flux OCIRepository is configured, when manifest changes, then Flux detects new artifact digest within 1 minute
- [ ] Given OCI artifact has SHA256 digest, when I reference artifact by digest, then deployment is immutable and reproducible

**Priority:** Must Have (Phase 1-2)

---

### FR-4: Infrastructure Layer Migration (Monitoring, APM, Databases)

**Description:** Migrate monitoring (Prometheus, Grafana), APM (Tempo, Pyroscope, Loki, Jaeger), and database operators (Zalando, CloudNativePG) from script-based deployment to Flux-managed Kustomize.

**User Story:**
> As a DevOps Engineer, I want to migrate infrastructure components to Flux so that monitoring/APM/databases are deployed declaratively and automatically reconciled.

**Acceptance Criteria:**
- [ ] Given infrastructure base manifests exist, when I apply Flux Kustomization, then Prometheus Operator, Grafana Operator deploy successfully
- [ ] Given APM base manifests exist, when I apply Flux Kustomization, then Tempo, Pyroscope, Loki, Vector, Jaeger deploy successfully
- [ ] Given database operators manifest exists, when I apply Flux Kustomization, then Zalando Postgres Operator and CloudNativePG Operator deploy successfully
- [ ] Given infrastructure Kustomization has `dependsOn`, when infrastructure reconciles, then apps wait for infrastructure to be ready
- [ ] Given local overlay patches exist, when I deploy locally, then infrastructure uses minimal resources (64Mi memory, 25m CPU)

**Priority:** Must Have (Phase 1)

**Note:** Database cluster CRDs (auth-db, review-db, product-db, transaction-db, supporting-db) migration is Phase 3 (complex, defer initially).

---

### FR-5: Microservices Layer Migration (9 Services + Frontend)

**Description:** Migrate 9 microservices (auth, user, product, cart, order, review, notification, shipping, shipping-v2) and frontend from Helm values files to Kustomize base/overlay manifests.

**User Story:**
> As a DevOps Engineer, I want to migrate all 9 microservices to Kustomize base/overlay so that I can eliminate 11 duplicate Helm values files and achieve zero duplication.

**Acceptance Criteria:**
- [ ] Given base manifests exist for all 9 services, when I run `kubectl apply -k base/apps`, then all services deploy with default configuration (2 replicas each)
- [ ] Given local overlay exists, when I run `kubectl apply -k overlays/local/apps`, then all services deploy with local configuration (1 replica, localhost:5050 registry)
- [ ] Given Flyway init containers are in base, when service deploys, then database migrations run automatically before main container starts
- [ ] Given Flux HelmRelease CRD exists (optional), when Helm chart updates, then Flux reconciles new chart version
- [ ] Given base is updated (e.g., add new env var), when I apply to overlays, then change propagates to all 9 services automatically

**Priority:** Must Have (Phase 2)

**Metrics:**
- Before: 11 Helm values files, ~900 lines, 80% duplication
- After: 1 base directory + 3 overlays, ~300 lines, 0% duplication
- Reduction: 67% fewer lines, 100% less duplication

---

### FR-6: Automated Reconciliation & Drift Detection

**Description:** Configure Flux to continuously reconcile cluster state from OCI artifacts and auto-heal manual changes (drift detection).

**User Story:**
> As a DevOps Engineer, I want Flux to automatically detect and fix manual kubectl changes so that cluster state always matches Git/OCI registry without manual intervention.

**Acceptance Criteria:**
- [ ] Given Flux Kustomization has `interval: 10m`, when 10 minutes pass, then Flux reconciles cluster state automatically
- [ ] Given I manually change a deployment replicas via `kubectl scale`, when Flux reconciles (within 10 min), then replicas revert to desired state from manifest
- [ ] Given I manually delete a service, when Flux reconciles with `prune: true`, then service is recreated automatically
- [ ] Given Flux detects drift, when I run `flux get kustomizations`, then I see last reconciliation time and status (Ready/Failed)
- [ ] Given reconciliation fails, when I check Flux logs, then I see detailed error message for troubleshooting

**Priority:** Must Have (Phase 1-2)

---

### FR-7: Flux Web UI Integration

**Description:** Deploy Flux Operator Web UI and configure port-forwarding for real-time visualization of Flux deployments, ResourceSets, and reconciliation status.

**User Story:**
> As a Developer or On-Call Engineer, I want to access Flux Web UI at http://localhost:9080 so that I can quickly view deployment status without running multiple kubectl commands.

**Acceptance Criteria:**
- [ ] Given Flux Operator is installed, when I run `kubectl port-forward -n flux-system svc/flux-operator 9080:9080`, then Web UI is accessible at http://localhost:9080
- [ ] Given Web UI is open, when I navigate to dashboard, then I see ResourceSet tree view showing infrastructure → apps hierarchy
- [ ] Given deployment is in progress, when I refresh Web UI, then I see real-time reconciliation status (Ready/Progressing/Failed)
- [ ] Given I search for "auth", when I submit search, then Web UI filters to show auth service status
- [ ] Given deployment fails, when I click on failed resource, then Web UI shows detailed error logs

**Priority:** Should Have (Phase 2)

**Integration:**
- Add to `scripts/08-setup-access.sh` for automatic port-forwarding
- Expected workflow: `./scripts/08-setup-access.sh` → open http://localhost:9080

---

### FR-8: Multi-Environment Support (Local/Staging/Production Overlays)

**Description:** Create separate Kustomize overlays for local, staging, and production environments with environment-specific patches (replicas, resources, image tags, HPA, PDB).

**User Story:**
> As a DevOps Engineer, I want to support multiple environments (local/staging/production) using the same base manifests so that I can ensure environment parity and clear promotion path.

**Acceptance Criteria:**
- [ ] Given local overlay exists, when I run `kubectl apply -k overlays/local`, then services deploy with local config (1 replica, minimal resources, localhost:5050 registry)
- [ ] Given staging overlay exists, when I run `kubectl apply -k overlays/staging`, then services deploy with staging config (2 replicas, medium resources, ghcr.io registry with staging tag)
- [ ] Given production overlay exists, when I run `kubectl apply -k overlays/production`, then services deploy with production config (3 replicas, full resources, HPA, PDB, ghcr.io:v6)
- [ ] Given I test locally and it works, when I promote to staging, then I only change overlay reference (not base manifests)
- [ ] Given production overlay has HPA, when CPU exceeds 70%, then HPA scales replicas from 3 to 10

**Priority:** Must Have (Phase 5)

**Promotion Flow:**
```
Local (test) → Staging (validate) → Production (deploy)
```

---

### FR-9: CI/CD Pipeline Integration (OCI Artifact Push)

**Description:** Automate manifest push to GitHub Container Registry (ghcr.io) on Git changes via GitHub Actions workflow.

**User Story:**
> As a DevOps Engineer, I want Git push to automatically push manifests to ghcr.io so that Flux can auto-sync from production registry without manual intervention.

**Acceptance Criteria:**
- [ ] Given GitHub Actions workflow exists, when I push to `main` branch with `kubernetes/**` changes, then workflow triggers
- [ ] Given workflow runs, when it completes, then manifests are pushed to `ghcr.io/duynhne/flux-infra-sync:main` and `ghcr.io/duynhne/flux-apps-sync:main`
- [ ] Given OCI artifacts are pushed to ghcr.io, when Flux reconciles (on production cluster), then it pulls from ghcr.io (not localhost:5050)
- [ ] Given workflow fails, when I check GitHub Actions logs, then I see error message for troubleshooting

**Priority:** Should Have (Phase 4)

**Note:** This is for future production deployment, not required for local Kind cluster.

---

### FR-10: Database CRD Migration (PostgreSQL Clusters)

**Description:** Migrate 5 PostgreSQL cluster CRDs (auth-db, review-db, supporting-db, product-db, transaction-db) from script-based deployment to Flux-managed Kustomization.

**User Story:**
> As a DevOps Engineer, I want to manage database clusters via Flux so that database lifecycle is declarative and version-controlled.

**Acceptance Criteria:**
- [ ] Given database CRDs exist in `base/infrastructure/databases/`, when I apply Flux Kustomization, then all 5 PostgreSQL clusters deploy successfully
- [ ] Given database Kustomization has `dependsOn: [database-operators]`, when operators are ready, then clusters deploy
- [ ] Given database secrets are generated, when microservices deploy, then they successfully connect to databases
- [ ] Given I delete database CRD manifest, when Flux reconciles with `prune: false`, then database clusters are NOT deleted (safety mechanism)
- [ ] Given database migration is idempotent, when I re-apply CRDs, then existing databases are not recreated (no data loss)

**Priority:** Should Have (Phase 3)

**Safety Note:** Database migration is complex and risky. Deferred to Phase 3 after infrastructure and apps are stable.

---

## 4. Non-Functional Requirements

### NFR-1: Performance

- **Deployment Time**: Reduce from 30 minutes (manual scripts) to < 5 minutes (Flux automated)
- **Reconciliation Interval**: Flux reconciles every 10 minutes (configurable down to 1 minute if needed)
- **OCI Artifact Sync**: Flux detects new OCI artifact digest within 1 minute
- **Web UI Load Time**: Flux Web UI loads within 2 seconds on local Kind cluster

**Measurement:**
```bash
time make flux-sync  # Should complete in < 5 minutes
```

### NFR-2: Reliability

- **Drift Auto-Healing**: Manual kubectl changes are reverted within 10 minutes (reconciliation interval)
- **Rollback Time**: Git revert + Flux reconcile completes within 2 minutes
- **Idempotency**: Re-applying Flux Kustomization has no side effects (safe to run multiple times)
- **Database Safety**: Database cluster CRDs have `prune: false` to prevent accidental deletion

**Error Budget:**
- Flux reconciliation success rate: > 99% (< 1% failures due to transient errors)

### NFR-3: Security

- **RBAC**: Flux service account has minimal required permissions (no cluster-admin)
- **Network Policies**: Flux controllers restricted to necessary network access only
- **Secret Encryption**: Secrets stored in Kubernetes Secrets (future: Sealed Secrets or SOPS)
- **OCI Artifact Signing**: (Future) Sign OCI artifacts with Cosign for supply chain security

**Note:** Advanced secret management (Sealed Secrets, SOPS) deferred to Phase 6 (out of scope for initial migration).

### NFR-4: Observability

- **Flux Metrics**: Prometheus scrapes Flux controller metrics (reconciliation duration, status)
- **Web UI Visibility**: Flux Web UI shows real-time status of all deployments
- **Logging**: Flux logs available via `kubectl logs -n flux-system` and Loki
- **Alerting**: (Future) Slack alerts for Flux reconciliation failures

**Key Metrics:**
```promql
flux_reconciler_duration_seconds_sum
flux_kustomization_ready_status
flux_helmrelease_ready_status
```

### NFR-5: Scalability

- **Microservices**: Support 9 microservices + frontend (10 total applications)
- **Infrastructure Components**: Support 20+ infrastructure components (operators, monitoring, APM, databases)
- **Environments**: Support 3 environments (local, staging, production) with same base manifests
- **Kustomize Build Time**: Kustomize build completes within 10 seconds for all overlays

### NFR-6: Maintainability

- **Documentation**: Complete documentation in `docs/gitops/` with examples
- **Code Duplication**: 0% duplication (Kustomize base/overlay pattern)
- **Configuration Centralization**: All configuration in `kubernetes/` directory (single source of truth)
- **Rollback Mechanism**: Git revert is the rollback mechanism (no manual Helm commands)

---

## 5. Out of Scope

The following are explicitly NOT included in this migration:

### ❌ ArgoCD Migration
**Reason:** Focus on Flux Operator only. ArgoCD has weaker OCI support and less flexibility for operator management. Decision documented in research.md comparison matrix.

### ❌ Progressive Delivery (Flagger)
**Reason:** Canary deployments and blue/green strategies are advanced patterns. Deferred to Phase 6 (future work) after core GitOps is stable.

### ❌ Secret Management (Sealed Secrets / SOPS)
**Reason:** Encrypt secrets in Git for production readiness. Deferred to Phase 6 (future work) as it adds complexity. Initial migration will use Kubernetes Secrets.

### ❌ Production Cluster Deployment
**Reason:** Focus on local Kind cluster for learning and validation. Production deployment (AWS EKS, GKE) is a separate project after mastering Flux locally.

### ❌ Multi-Cluster Federation
**Reason:** Managing multiple Kubernetes clusters (staging, production) from single Flux instance. Deferred as initial scope is single-cluster (local Kind).

### ❌ Image Update Automation
**Reason:** Automatically update image tags in manifests when new images are pushed to ghcr.io. Deferred as it requires Flux Image Automation Controllers and adds complexity.

### ❌ Flux Multi-Tenancy
**Reason:** Isolating Flux access per team/tenant. Not needed as this is a personal learning project with single user (DevOps/SRE).

### ❌ Custom Flux Operator Controllers
**Reason:** Extending Flux with custom CRDs or controllers. Out of scope as this is a migration project, not a Flux development project.

---

## 6. Edge Cases & Error Handling

### Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| **Flux Operator fails to install** | Script exits with error, keeps existing deployment scripts as fallback |
| **OCI registry localhost:5050 is down** | Flux reconciliation fails, retries every 1 minute until registry is back |
| **Kustomize build fails (invalid YAML)** | Flux marks Kustomization as "Failed" with error message in Web UI, does not apply changes |
| **Base manifest is invalid** | Overlays fail to build, Flux does not deploy broken configuration |
| **Database CRD is accidentally deleted** | `prune: false` prevents deletion, manual confirmation required |
| **Manual kubectl change during reconciliation** | Flux may conflict with manual change, last-write-wins (Flux state takes precedence) |
| **Init container (Flyway) fails** | Main container does not start, Deployment stays in "Pending" state, logs show migration error |
| **Namespace already exists** | Kustomize applies successfully (idempotent), no error |
| **HPA scales beyond maxReplicas** | HPA enforces maxReplicas limit, additional pods are not created |
| **Local registry runs out of disk space** | OCI artifact push fails, workflow retries or fails with clear error |

### Error Scenarios

| Error | User Message | System Action |
|-------|--------------|---------------|
| **Flux reconciliation timeout (5 min)** | "Kustomization 'apps-local' reconciliation timed out" | Flux retries after `retryInterval: 2m`, Web UI shows "Failed" status |
| **OCI artifact not found (404)** | "OCIRepository 'flux-apps-sync' artifact not found: oci://localhost:5050/flux-apps-sync:local" | Flux waits for artifact to appear, reconciliation fails until artifact is pushed |
| **Invalid Kustomization path** | "Path './kubernetes/overlays/local/apps' not found in artifact" | Flux marks Kustomization as "Failed", does not apply changes |
| **Dependency not ready** | "Kustomization 'apps-local' waiting for dependency 'infrastructure-local' to be ready" | Flux waits until dependency is ready, then reconciles |
| **Database migration fails (Flyway)** | "Init container 'flyway-migration' exited with code 1" | Pod stays in "Init:Error" state, Deployment never becomes ready, logs show SQL error |
| **Secret not found** | "Error creating container: secret 'auth.auth-db.credentials' not found" | Pod stays in "Pending" state, Deployment never becomes ready |
| **Port-forward fails (port already in use)** | "Error: unable to forward port 9080, port is already allocated" | Script exits with error, suggests killing existing port-forward process |
| **Kustomize overlay patch conflict** | "Error: patch conflict for Deployment 'auth'" | Kustomize build fails, Flux does not apply changes, Web UI shows error message |

---

## 7. Success Metrics

### Key Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Deployment Time Reduction** | < 5 minutes (from 30 min) | `time make flux-sync` |
| **Configuration Duplication** | 0% (from 80%) | Count of unique vs duplicated lines in `kubernetes/` vs `charts/mop/values/` |
| **Drift Incidents Prevented** | > 10 per month | Flux auto-heals manual kubectl changes (count reconciliations) |
| **Environment Parity** | 100% | Same base manifests used in local/staging/production |
| **Reconciliation Success Rate** | > 99% | `flux get kustomizations` success rate over 30 days |
| **Web UI Adoption** | > 50% team usage | Track Web UI access logs (port-forward usage) |
| **Learning Outcomes** | Master Flux + Kustomize | Complete all 5 phases, document learnings in portfolio |
| **Career Impact** | Senior SRE promotion | Demonstrate GitOps expertise to management |

### Definition of Done

**Phase 1-2 (Foundation + Apps):**
- [ ] Flux Operator installed and running on local Kind cluster
- [ ] Infrastructure components (monitoring, APM, databases) deployed via Flux
- [ ] All 9 microservices + frontend deployed via Kustomize overlays
- [ ] Configuration duplication reduced from 900 → 300 lines (67% reduction)
- [ ] Flux Web UI accessible at http://localhost:9080
- [ ] Drift detection working (manual changes reverted within 10 min)
- [ ] Existing scripts still work as fallback

**Phase 3 (Databases):**
- [ ] 5 PostgreSQL cluster CRDs managed by Flux
- [ ] Database operators managed by Flux
- [ ] Migration is idempotent (re-applying does not break existing DBs)

**Phase 4 (CI/CD):**
- [ ] GitHub Actions workflow pushes manifests to ghcr.io
- [ ] Flux syncs from ghcr.io (production registry)

**Phase 5 (Multi-Environment):**
- [ ] Staging and production overlays created
- [ ] Same base manifests used in all environments
- [ ] Clear promotion path: local → staging → production
- [ ] Production overlay includes HPA, PDB, anti-affinity

---

## 8. Open Questions

- [ ] **Secret Management Strategy**: Should we use Sealed Secrets or SOPS in Phase 6? (Deferred, not blocking)
- [ ] **Image Update Automation**: Enable automated image updates for v6 minor versions? (Deferred, not blocking)
- [ ] **Production Cluster Platform**: Deploy to AWS EKS or GKE? (Deferred, focus on local Kind first)
- [ ] **Team Training**: How many workshops needed for team to adopt Flux? (TBD after Phase 2 completion)
- [ ] **Commercial Support**: Should we purchase ControlPlane.io support for Flux Operator? (Decide after Phase 5)

---

## 9. Migration Phases

### Phase 1: Foundation (Week 1-2)

**Goal:** Establish Flux Operator foundation and migrate infrastructure components.

**Deliverables:**
- Flux Operator installed on local Kind cluster
- Kustomize repository structure created (`base/`, `overlays/`, `clusters/`)
- Infrastructure components (monitoring, APM, database operators) migrated
- Makefile automation (`make flux-up`, `make flux-push`, `make flux-sync`)

**Acceptance Criteria:**
- [ ] Flux Operator running in `flux-system` namespace
- [ ] `kubectl apply -k kubernetes/overlays/local/infrastructure` builds successfully
- [ ] Flux auto-syncs infrastructure from base + local overlay
- [ ] Existing scripts still work (parallel operation)

---

### Phase 2: Microservices Migration (Week 3-4)

**Goal:** Migrate 9 microservices + frontend to Kustomize overlays.

**Deliverables:**
- Base manifests for all 9 services + frontend
- Local overlay with patches (1 replica, minimal resources, localhost:5050 registry)
- Flux Kustomization CRD for apps layer
- Flux Web UI integration

**Acceptance Criteria:**
- [ ] All services have base manifests in `kubernetes/base/apps/`
- [ ] `kubectl apply -k kubernetes/overlays/local/apps` builds successfully
- [ ] Flux auto-syncs services from base + local overlay
- [ ] Flux Web UI accessible at http://localhost:9080
- [ ] Configuration duplication reduced from 900 → 300 lines

---

### Phase 3: Database CRDs Migration (Week 5-6)

**Goal:** Migrate 5 PostgreSQL cluster CRDs to Flux management.

**Deliverables:**
- Database cluster CRDs in `base/infrastructure/databases/`
- Flux Kustomization with `dependsOn: [database-operators]`
- Idempotent migration (re-applying does not break DBs)

**Acceptance Criteria:**
- [ ] Database clusters managed by Flux
- [ ] Migration is idempotent (re-applying CRDs doesn't break existing DBs)
- [ ] Database connection secrets available before microservices start

---

### Phase 4: CI/CD Integration (Week 7-8)

**Goal:** Automate manifest push to ghcr.io on Git changes.

**Deliverables:**
- GitHub Actions workflow for manifest push
- FluxInstance configured for production registry (ghcr.io)

**Acceptance Criteria:**
- [ ] Git push triggers manifest push to ghcr.io
- [ ] Flux auto-syncs from ghcr.io artifacts
- [ ] No manual intervention required

---

### Phase 5: Multi-Environment Setup (Week 9-10)

**Goal:** Support local/staging/production environments using Kustomize overlays.

**Deliverables:**
- Staging and production overlays with environment-specific patches
- Kustomize components for HA (HPA, PDB, anti-affinity)
- Cluster configurations for staging/production

**Acceptance Criteria:**
- [ ] Same base manifests deployed to all environments
- [ ] Environment-specific configuration via Kustomize patches
- [ ] No code duplication (DRY principle)
- [ ] Clear promotion path: local → staging → production
- [ ] Production includes HA features (HPA, PDB, anti-affinity)

---

## 10. Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-01-10 | Initial specification | DevOps/SRE Engineer |

---

## Next Steps

1. **Review Specification**: Review with team/stakeholders (if applicable)
2. **Resolve Open Questions**: Decide on deferred items (secret management, production cluster)
3. **Create Technical Plan**: Run `/plan flux-gitops-migration` to create detailed implementation plan
4. **Break Down Tasks**: Run `/tasks flux-gitops-migration` to generate actionable task list
5. **Start Phase 1**: Begin with Flux Operator installation and infrastructure migration

---

*Specification created with SDD 2.0*
