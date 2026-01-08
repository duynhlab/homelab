# Specification: Zalando Postgres Operator Production-Ready Configuration

**Task ID:** Zalando-operator
**Created:** 2025-12-26
**Status:** Ready for Planning
**Version:** 2.4 (Added PostgreSQL Monitoring Requirements)

**Related Documents:**
- Research: `specs/active/Zalando-operator/research.md`
- Decision: Enable `enable_cross_namespace_secret` feature (APPROVED)

---

## 1. Problem Statement

### The Problem

This specification addresses **three critical production-ready requirements** for Zalando Postgres Operator-managed PostgreSQL clusters:

1. **Cross-Namespace Secret Management**: The **Supporting Database** (`supporting-db`) cluster uses a shared database pattern where multiple services (User, Notification, Shipping-v2) share the same PostgreSQL cluster but deploy in different Kubernetes namespaces. Zalando Postgres Operator creates database user secrets in the cluster's namespace (`user`), but services in other namespaces (`notification`, `shipping`) cannot access these secrets due to Kubernetes namespace isolation.

2. **PostgreSQL Performance Tuning**: Current database configurations use minimal default parameters that are not optimized for production workloads. DevOps/SRE teams need comprehensive tuning guidance for memory, WAL, query planner, parallelism, autovacuum, and logging settings to ensure optimal performance and reliability.

3. **Password Rotation & Backup Strategy**: Production databases require secure password rotation procedures and robust backup/disaster recovery strategies. Current setup lacks documented procedures for password rotation and backup configuration (WAL-E/WAL-G, PITR).

**Kubernetes Limitation:** `secretKeyRef` in pod specs can **ONLY** reference secrets in the **same namespace** as the pod. There is **NO** way to reference secrets across namespaces using `secretKeyRef`.

### Current Situation

**Current Workaround:**
- Zalando operator creates secrets in `user` namespace:
  - `notification.notification.supporting-db.credentials.postgresql.acid.zalan.do` (in `user` namespace)
  - `shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do` (in `user` namespace)
- Manual sync script (`scripts/04b-sync-supporting-db-secrets.sh`) copies secrets to target namespaces
- Script runs after database deployment, waits for secrets, then copies them using `kubectl get secret ... -o yaml | sed ... | kubectl apply`

**Critical Issue Discovered (2025-12-30):**
- **Root Cause**: `k8s/postgres-operator-zalando/values.yaml` uses **incorrect nested structure** (`config.kubernetes.enable_cross_namespace_secret`) instead of **flat structure** (`configKubernetes.enable_cross_namespace_secret`) as required by Helm chart defaults
- **Impact**: Operator cannot read `enable_cross_namespace_secret` setting because it's in wrong location
- **Result**: Cross-namespace secret feature is configured but not actually enabled, causing secrets to be created in `user` namespace instead of target namespaces
- **Services Affected**: `notification`, `shipping`, `shipping-v2` services failing with "secret not found" errors

**Pain Points:**
- ❌ **CRITICAL**: Helm values structure prevents operator from reading configuration
- ❌ Requires custom sync script maintenance
- ❌ Potential timing issues (secrets may not exist when script runs)
- ❌ Not declarative (imperative sync)
- ❌ Secrets can get out of sync if operator updates them
- ❌ Additional operational overhead
- ❌ Not aligned with Kubernetes best practices (declarative configuration)
- ❌ `shipping-v2` service references user `shipping` but CRD only has `shipping.shipping` user

### Desired Outcome

**Phase 1: Cross-Namespace Secrets (Immediate)**
Enable Zalando Postgres Operator's native `enable_cross_namespace_secret` feature to automatically create secrets in target namespaces. This will:
- ✅ Eliminate need for manual sync script
- ✅ Provide declarative, operator-managed secret creation
- ✅ Ensure secrets stay in sync automatically
- ✅ Reduce operational overhead
- ✅ Align with Kubernetes best practices

**Phase 2: Production-Ready Configuration (DevOps/SRE Requirements)**
- ✅ **PostgreSQL Performance Tuning**: Comprehensive parameter tuning for optimal performance (memory, WAL, query planner, parallelism, autovacuum, logging)
- ✅ **Password Rotation**: Secure password rotation procedures (native Zalando and External Secrets Operator approaches)
- ✅ **Backup Strategy**: WAL-E/WAL-G backup configuration, Point-in-Time Recovery (PITR), disaster recovery planning

**Future Integration:**
- ✅ Enable future integration with External Secrets Operator/Vault for automated password rotation

---

## 2. User Personas

### Primary User: DevOps/SRE Engineer

- **Who:** Platform/DevOps/SRE engineer responsible for Kubernetes infrastructure and database operations in production environments
- **Goals:** 
  - Maintain clean, declarative infrastructure configuration
  - Reduce manual operational tasks
  - Ensure secrets are properly managed and synchronized
  - Optimize PostgreSQL performance for production workloads
  - Implement secure password rotation procedures
  - Configure robust backup and disaster recovery strategies
  - Enable future extensibility with external secret management (Vault)
- **Pain points:** 
  - Maintaining custom sync scripts
  - Dealing with timing issues when secrets aren't ready
  - Manual secret synchronization overhead
  - Lack of production-ready PostgreSQL tuning guidance
  - No documented password rotation procedures
  - Missing backup configuration and disaster recovery planning
- **Tech comfort:** High - Expert in Kubernetes, operators, PostgreSQL, and infrastructure automation

### Secondary User: Developer

- **Who:** Application developer deploying services that need database access
- **Goals:**
  - Deploy services without worrying about secret synchronization
  - Have secrets available in correct namespaces automatically
  - Focus on application code, not infrastructure
- **Pain points:**
  - Services failing to start due to missing secrets
  - Needing to understand secret sync process
  - Waiting for manual sync operations
- **Tech comfort:** Medium - Familiar with Kubernetes but not deep infrastructure details

---

## 3. Functional Requirements

### FR-1: Fix Helm Values Structure (CRITICAL)

**Description:** Fix the incorrect Helm values structure in `k8s/postgres-operator-zalando/values.yaml` to use flat structure (`configKubernetes:`, `configGeneral:`, etc.) instead of nested structure (`config:`), enabling the operator to read the `enable_cross_namespace_secret` setting.

**User Story:**
> As a **DevOps engineer**, I want to **fix the Helm values structure** so that **the operator can correctly read the `enable_cross_namespace_secret` configuration and create secrets in target namespaces**.

**Acceptance Criteria:**
- [ ] Helm values file (`k8s/postgres-operator/zalando/values.yaml`) restructured to use flat structure with correct field names:
  - Replace nested `config:` with flat `configKubernetes:`, `configGeneral:`, `configUsers:`, etc.
  - Fix `cluster_name` → `cluster_domain` (field name correction)
  - Fix `configConnectionPooler.default_parameters` → direct fields (structure correction)
  - Remove `configPostgresql.parameters` (parameters set in CRDs, not operator config)
  - Fix `configBackup` → `configAwsOrGcp` (section name correction)
  - Move `enable_cross_namespace_secret: true` to `configKubernetes.enable_cross_namespace_secret: true`
- [ ] Image configuration updated to use `ghcr.io/zalando/postgres-operator:v1.15.1`
- [ ] Helm release upgraded with corrected values.yaml
- [ ] Operator pod restarts and becomes ready
- [ ] OperatorConfiguration CRD shows `enable_cross_namespace_secret: true` is set
- [ ] Operator logs confirm feature is enabled
- [ ] No impact on existing clusters (`auth-db`, `review-db`) that don't use namespace notation

**Priority:** Must Have (CRITICAL - DO FIRST)

**Technical Details:**
- **Current (WRONG)**:
  ```yaml
  config:
    kubernetes:
      cluster_name: "kind-cluster"  # ❌ WRONG: Should be cluster_domain
      enable_cross_namespace_secret: true
    connection_pooler:
      default_parameters:  # ❌ WRONG: Nested structure doesn't exist
        pool_mode: "transaction"
    postgresql:
      parameters:  # ❌ WRONG: configPostgresql.parameters doesn't exist
        max_connections: "100"
    backup:  # ❌ WRONG: Should be configAwsOrGcp
      wal_s3_bucket: ""
  ```
- **Correct (per Helm chart defaults)**:
  ```yaml
  configKubernetes:
    cluster_domain: cluster.local  # ✅ Correct field name
    enable_cross_namespace_secret: true
  
  configConnectionPooler:
    connection_pooler_schema: "pooler"  # ✅ Direct fields, not nested
    connection_pooler_user: "pooler"
    connection_pooler_mode: "transaction"
    connection_pooler_number_of_instances: 2
    connection_pooler_max_db_connections: 60
    connection_pooler_default_cpu_request: 500m
    connection_pooler_default_memory_request: 100Mi
  
  configAwsOrGcp:  # ✅ Correct section name
    aws_region: eu-central-1
    wal_s3_bucket: ""
  
  configGeneral:
    enable_pgversion_env_var: true
  
  # Note: configPostgresql.parameters does NOT exist
  # PostgreSQL parameters are set per-cluster in CRDs (postgresql resources)
  ```
- **Key Corrections:**
  - `cluster_name` → `cluster_domain` (field name correction)
  - `configConnectionPooler.default_parameters` → direct fields (structure correction)
  - `configPostgresql.parameters` → removed (parameters set in CRDs, not operator config)
  - `configBackup` → `configAwsOrGcp` (section name correction)
- Helm chart expects flat structure as top-level keys, NOT nested under `config`
- Image: `ghcr.io/zalando/postgres-operator:v1.15.1` (official multi-arch image)

### FR-2: Enable Cross-Namespace Secret Feature in Zalando Operator

**Description:** Verify that Zalando Postgres Operator correctly reads the `enable_cross_namespace_secret` feature after fixing Helm values structure, allowing secrets to be created directly in target namespaces based on user name format.

**User Story:**
> As a **DevOps engineer**, I want to **verify the operator correctly reads the cross-namespace secret configuration** so that **secrets are automatically created in the correct namespaces without manual sync scripts**.

**Acceptance Criteria:**
- [ ] OperatorConfiguration CRD shows `enable_cross_namespace_secret: true` is set
- [ ] Operator logs confirm feature is enabled (no errors about configuration)
- [ ] CRD format verified (uses `namespace.username` format)
- [ ] Secrets recreated after configuration fix (delete old secrets to trigger recreation)
- [ ] Operator logs show cross-namespace secret creation attempts
- [ ] RBAC permissions verified (operator can create secrets in target namespaces)
- [ ] No impact on existing clusters (`auth-db`, `review-db`) that don't use namespace notation

**Priority:** Must Have

**Technical Details:**
- Configuration method: Helm values.yaml (which creates OperatorConfiguration CRD)
- Field: `configKubernetes.enable_cross_namespace_secret: true` (flat structure)
- No `secret_name_template` needed - operator uses default template automatically
- Bugfix #2912 in v1.15.0 fixes secret creation in other namespaces when using preparedDatabases and OwnerReference

### FR-3: Update Database CRD with Namespace Notation and Add Missing User

**Description:** Update `supporting-db.yaml` CRD to use `namespace.username` format for users that need secrets in different namespaces.

**User Story:**
> As a **DevOps engineer**, I want to **specify namespace notation in database CRD** so that **operator creates secrets in the correct target namespaces**.

**Acceptance Criteria:**
- [ ] Database CRD (`k8s/postgres-operator-zalando/crds/supporting-db.yaml`) updated with namespace notation:
  - `notification.notification` instead of `notification` (format: `namespace.username`)
  - `shipping.shipping` instead of `shipping` (format: `namespace.username`)
- [ ] **NEW**: Add missing `shipping` user (without namespace prefix) for `shipping-v2` service:
  - User: `shipping` (creates secret `shipping.supporting-db.credentials.postgresql.acid.zalan.do` in `user` namespace)
  - Database `shipping` already exists (owned by `shipping.shipping`), so only user needs to be added
- [ ] Database section updated to match user format:
  - `notification: notification.notification`
  - `shipping: shipping.shipping` (database owned by `shipping.shipping`)
- [ ] CRD applied successfully
- [ ] Operator recognizes namespace notation format (anything before first dot = namespace, after first dot = username)
- [ ] Operator creates `shipping.supporting-db.credentials.postgresql.acid.zalan.do` secret in `user` namespace after CRD update

**Priority:** Must Have

**Technical Details:**
- Format: `namespace.username` (dot notation, not `@`)
- Example: `notification.notification` → namespace: `notification`, username: `notification`
- Postgres role name will be: `namespace.username` (e.g., `notification.notification`)
- `shipping-v2` service uses user `shipping` (no namespace prefix), so secret is created in cluster namespace (`user`)

### FR-4: Create Fallback Secret YAML Files (If Operator Doesn't Create Secrets)

**Description:** Create declarative YAML files to manually copy secrets from `user` namespace to target namespaces as a fallback solution if the operator still doesn't create secrets in target namespaces after fixing configuration.

**User Story:**
> As a **DevOps engineer**, I want to **create declarative secret YAML files** so that **secrets can be manually copied to target namespaces if the operator fails to create them automatically**.

**Acceptance Criteria:**
- [ ] Secret YAML file created: `k8s/secrets/notification-supporting-db-secret.yaml`
  - Secret name: `notification.notification.supporting-db.credentials.postgresql.acid.zalan.do`
  - Namespace: `notification`
  - Copies `username` and `password` keys from source secret in `user` namespace
- [ ] Secret YAML file created: `k8s/secrets/shipping-supporting-db-secret.yaml`
  - Secret name: `shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do`
  - Namespace: `shipping`
  - Copies `username` and `password` keys from source secret in `user` namespace
- [ ] Secret YAML file created: `k8s/secrets/shipping-v2-supporting-db-secret.yaml`
  - Secret name: `shipping.supporting-db.credentials.postgresql.acid.zalan.do`
  - Namespace: `shipping`
  - Copies `username` and `password` keys from source secret in `user` namespace
  - Note: This secret is created after CRD update (when `shipping` user is added)
- [ ] Deployment script (`scripts/04-deploy-databases.sh`) updated to apply secret YAML files if needed
- [ ] Secrets can be applied declaratively using `kubectl apply -f k8s/secrets/`

**Priority:** Should Have (Fallback Solution - Only if Phase 0 fails)

**Technical Details:**
- Secret type: `Opaque`
- Secret data: `username` and `password` keys (base64 encoded)
- Source: Extract from secrets in `user` namespace
- Target: Apply to `notification` and `shipping` namespaces
- No manual `kubectl` commands needed (all via YAML files)

### FR-5: Update Helm Values for Secret References

**Description:** Update Helm values files for `notification`, `shipping`, and `shipping-v2` services to reference correct secret names.

**User Story:**
> As a **developer**, I want to **reference secrets using the correct naming format** so that **services can access database credentials from their own namespaces**.

**Acceptance Criteria:**
- [ ] Helm values (`charts/values/notification.yaml`) updated with secret name:
  - Secret: `notification.notification.supporting-db.credentials.postgresql.acid.zalan.do`
  - Namespace: `notification` (implicit - same as pod namespace)
- [ ] Helm values (`charts/values/shipping.yaml`) updated with secret name:
  - Secret: `shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do`
  - Namespace: `shipping` (implicit - same as pod namespace)
- [ ] Helm values (`charts/values/shipping-v2.yaml`) updated with secret name:
  - Secret: `shipping.supporting-db.credentials.postgresql.acid.zalan.do`
  - Namespace: `shipping` (implicit - same as pod namespace)
  - Note: This secret is in `user` namespace, but `shipping-v2` service is in `shipping` namespace, so manual copy needed
- [ ] Secret references use `secretKeyRef` with correct namespace (implicit - same as pod namespace)
- [ ] Services deploy successfully and can access secrets

**Priority:** Must Have

**Technical Details:**
- Secret name format: `{namespace}.{username}.{clustername}.credentials.postgresql.acid.zalan.do`
- Example: `notification.notification.supporting-db.credentials.postgresql.acid.zalan.do`
- Secret created in `notification` namespace automatically by operator (or via fallback YAML)
- `shipping-v2` service needs manual secret copy since it uses user `shipping` (no namespace prefix)

### FR-6: Verify Secret Creation and Service Access

**Description:** Verify that secrets are created in correct namespaces and services can access them successfully.

**User Story:**
> As a **DevOps engineer**, I want to **verify secrets are created correctly** so that **services can access database credentials without errors**.

**Acceptance Criteria:**
- [ ] Secrets created in correct namespaces:
  - `notification.notification.supporting-db.credentials.postgresql.acid.zalan.do` in `notification` namespace
  - `shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do` in `shipping` namespace
  - `shipping.supporting-db.credentials.postgresql.acid.zalan.do` in `shipping` namespace (manually copied for shipping-v2)
- [ ] Secrets contain required keys: `username`, `password`
- [ ] Notification service pod can access secret and connect to database
- [ ] Shipping service pod can access secret and connect to database
- [ ] Shipping-v2 service pod can access secret and connect to database
- [ ] No "secret not found" errors in service logs
- [ ] Database connections successful
- [ ] All three services (`notification`, `shipping`, `shipping-v2`) start successfully

**Priority:** Must Have

**Verification Steps:**
```bash
# Check secrets exist in correct namespaces
kubectl get secret notification.notification.supporting-db.credentials.postgresql.acid.zalan.do -n notification
kubectl get secret shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do -n shipping
kubectl get secret shipping.supporting-db.credentials.postgresql.acid.zalan.do -n shipping

# Verify secret data (username should match)
kubectl get secret notification.notification.supporting-db.credentials.postgresql.acid.zalan.do -n notification -o jsonpath='{.data.username}' | base64 -d && echo ""
kubectl get secret shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do -n shipping -o jsonpath='{.data.username}' | base64 -d && echo ""
kubectl get secret shipping.supporting-db.credentials.postgresql.acid.zalan.do -n shipping -o jsonpath='{.data.username}' | base64 -d && echo ""

# Check services can start
kubectl get pods -n notification -l app=notification
kubectl get pods -n shipping -l app=shipping
kubectl get pods -n shipping -l app=shipping-v2
```

### FR-7: Remove Manual Sync Script

**Description:** Remove the manual secret sync script and its invocation from deployment scripts after successful verification.

**User Story:**
> As a **DevOps engineer**, I want to **remove the manual sync script** so that **we eliminate maintenance overhead and rely on operator-managed secrets**.

**Acceptance Criteria:**
- [ ] Sync script (`scripts/04b-sync-supporting-db-secrets.sh`) deleted
- [ ] Script invocation removed from `scripts/04-deploy-databases.sh`
- [ ] Deployment process works without sync script
- [ ] Documentation updated to reflect removal of sync script
- [ ] No references to sync script in codebase (except historical documentation)

**Priority:** Must Have

**Cleanup Steps:**
- Delete `scripts/04b-sync-supporting-db-secrets.sh`
- Remove sync script call from `scripts/04-deploy-databases.sh`
- Update `docs/guides/DATABASE.md` to remove sync script references
- Update `CHANGELOG.md` with changes

### FR-8: Handle Existing Secrets Migration

**Description:** Clean up old secrets in `user` namespace that are no longer needed after migration.

**User Story:**
> As a **DevOps engineer**, I want to **clean up old secrets** so that **we don't have orphaned secrets cluttering the namespace**.

**Acceptance Criteria:**
- [ ] Old secrets in `user` namespace identified:
  - `notification.supporting-db.credentials.postgresql.acid.zalan.do`
  - `shipping.supporting-db.credentials.postgresql.acid.zalan.do`
- [ ] Old secrets deleted after new secrets are verified in target namespaces
- [ ] No service downtime during secret migration
- [ ] Verification that services continue working after old secrets deletion

**Priority:** Should Have

**Migration Approach:**
- No migration needed - can delete old secrets and redeploy
- Operator will recreate secrets in correct namespaces automatically
- Services will use new secrets from their own namespaces

### FR-9: Configure PostgreSQL Performance Tuning Parameters

**Description:** Apply production-ready PostgreSQL parameter tuning to all Zalando-managed clusters, optimizing memory, WAL, query planner, parallelism, autovacuum, and logging settings.

**User Story:**
> As a **DevOps/SRE engineer**, I want to **configure production-ready PostgreSQL tuning parameters** so that **databases perform optimally with proper resource utilization, query performance, and observability**.

**Acceptance Criteria:**
- [ ] Memory settings configured (shared_buffers, work_mem, maintenance_work_mem, effective_cache_size)
- [ ] WAL settings optimized (wal_buffers, checkpoint_timeout, max_wal_size, min_wal_size)
- [ ] Query planner tuned for storage type (random_page_cost, effective_io_concurrency)
- [ ] Parallelism configured (max_worker_processes, max_parallel_workers)
- [ ] Autovacuum settings optimized (autovacuum_max_workers, autovacuum_vacuum_scale_factor)
- [ ] Logging configured (log_statement, log_min_duration_statement, log_lock_waits, log_connections)
- [ ] Parameters applied to all Zalando-managed clusters (auth-db, review-db, supporting-db)
- [ ] Performance improvements verified (cache hit ratio >95%, reduced query times)

**Priority:** Should Have

**Technical Details:**
- Configuration via `postgresql.parameters` in database CRDs
- Example values documented in research.md
- Tuning guidelines provided for different workload types
- Monitoring metrics defined for validation

### FR-10: Implement Password Rotation Procedures

**Description:** Document and implement secure password rotation procedures for Zalando-managed database credentials, supporting both native Zalando approach and External Secrets Operator integration.

**User Story:**
> As a **DevOps/SRE engineer**, I want to **rotate database passwords securely** so that **we comply with security policies and maintain zero-downtime operations**.

**Acceptance Criteria:**
- [ ] Native Zalando password rotation procedure documented
- [ ] Zero-downtime rotation strategy defined
- [ ] External Secrets Operator approach documented (for future integration)
- [ ] Rotation schedule defined (infrastructure roles: 90 days, application users: 180 days)
- [ ] Rotation procedures tested in staging environment
- [ ] Monitoring and alerting configured for password age
- [ ] Rollback procedures documented

**Priority:** Should Have

**Technical Details:**
- Native approach: Manual secret updates with operator watching
- ESO approach: Automatic rotation from Vault/AWS Secrets Manager
- Dual password strategy for zero-downtime
- Rotation frequency based on security policy

### FR-11: Configure Backup Strategy

**Description:** Configure WAL-E/WAL-G backup for continuous WAL archiving and implement backup retention policies, Point-in-Time Recovery (PITR), and disaster recovery procedures.

**User Story:**
> As a **DevOps/SRE engineer**, I want to **configure comprehensive backup and disaster recovery** so that **we can recover from data loss and meet RTO/RPO requirements**.

**Acceptance Criteria:**
- [ ] WAL-E/WAL-G backup configured (S3/GCS/Azure)
- [ ] Backup retention policies defined (daily: 30 days, weekly: 12 weeks, monthly: 12 months)
- [ ] Point-in-Time Recovery (PITR) procedures documented
- [ ] Disaster recovery plan created (RTO: 4 hours, RPO: 15 minutes)
- [ ] Backup monitoring and alerting configured
- [ ] Restore testing procedures documented
- [ ] Backup health checks automated

**Priority:** Nice to Have (Future Phase)

**Technical Details:**
- WAL-E/WAL-G configuration via Spilo environment variables
- S3 bucket with lifecycle policies
- Logical backups via Kubernetes CronJobs
- Backup verification and restore testing procedures

### FR-12: Deploy Postgres Operator UI Component

**Description:** Deploy the optional Postgres Operator UI component to provide a graphical web interface for managing PostgreSQL clusters. The UI enables DevOps/SRE teams and developers to view, create, and manage database clusters through a convenient web interface.

**User Story:**
> As a **DevOps/SRE engineer**, I want to **deploy Postgres Operator UI** so that **teams can manage database clusters through a web interface without requiring kubectl access**.

**Acceptance Criteria:**
- [ ] Helm values file created: `k8s/postgres-operator/zalando/ui-values.yaml`
- [ ] UI configured to connect to operator API: `http://postgres-operator.database.svc.cluster.local:8080`
- [ ] UI configured to view all namespaces: `targetNamespace: "*"`
- [ ] UI deployed in `database` namespace (or `monitoring` namespace)
- [ ] UI service accessible via port-forward: `kubectl port-forward -n database svc/postgres-operator-ui 8081:80`
- [ ] UI displays all PostgreSQL clusters (`auth-db`, `review-db`, `supporting-db`)
- [ ] UI allows viewing cluster status and details
- [ ] Optional: Ingress configured for external access (if needed)
- [ ] Documentation updated with UI access instructions

**Priority:** Nice to Have (Optional Enhancement)

**Technical Details:**
- **Chart**: `postgres-operator-ui-charts/postgres-operator-ui`
- **Version**: `1.15.1` (matches operator version)
- **Image**: `ghcr.io/zalando/postgres-operator-ui:v1.15.1`
- **Namespace**: `database` (recommended) or `monitoring`
- **Service Type**: `ClusterIP` (default) or `NodePort`/`Ingress` for external access
- **Operator API URL**: `http://postgres-operator.database.svc.cluster.local:8080`
- **Target Namespace**: `"*"` to view all namespaces

**Configuration Example:**
```yaml
# k8s/postgres-operator/zalando/ui-values.yaml
replicaCount: 1

image:
  registry: ghcr.io
  repository: zalando/postgres-operator-ui
  tag: v1.15.1
  pullPolicy: IfNotPresent

envs:
  appUrl: "http://localhost:8081"
  operatorApiUrl: "http://postgres-operator.database.svc.cluster.local:8080"
  operatorClusterNameLabel: "cluster-name"
  resourcesVisible: "False"
  targetNamespace: "*"  # View all namespaces
  teams: []  # Empty if not using Teams API

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false  # Enable if external access needed
```

**Deployment Command:**
```bash
helm repo add postgres-operator-ui-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator-ui
helm upgrade --install postgres-operator-ui postgres-operator-ui-charts/postgres-operator-ui \
  -f k8s/postgres-operator/zalando/ui-values.yaml \
  -n database \
  --version 1.15.1 \
  --wait
```

**Access Methods:**
1. **Port-forward** (recommended for development):
   ```bash
   kubectl port-forward -n database svc/postgres-operator-ui 8081:80
   # Access: http://localhost:8081
   ```

2. **Ingress** (for production external access):
   - Enable ingress in values.yaml
   - Configure hostname and TLS
   - Access via external URL

**Benefits:**
- ✅ Visual cluster management interface
- ✅ Multi-namespace cluster visibility
- ✅ Reduced kubectl dependency for developers
- ✅ Self-service cluster creation (if enabled)
- ✅ Quick status checks without command-line access

---

## 4. Non-Functional Requirements

### NFR-1: Compatibility

- **Requirement:** Solution must be compatible with Zalando Postgres Operator v1.15.0
- **Verification:** Feature confirmed supported in v1.15.0 (from research)
- **Impact:** No operator upgrade needed

### NFR-2: Zero Downtime

- **Requirement:** Migration must not cause service downtime
- **Approach:** 
  - Update configurations first
  - Verify new secrets created before removing old ones
  - Services continue using existing secrets until new ones are ready
- **Verification:** Services remain running during migration

### NFR-3: No Impact on Other Clusters

- **Requirement:** Changes must not affect other database clusters (`auth-db`, `review-db`)
- **Verification:** 
  - `enable_cross_namespace_secret` only affects clusters using `namespace.username` format
  - Other clusters continue working normally
  - No changes needed for `auth-db` and `review-db`

### NFR-4: Future Extensibility

- **Requirement:** Solution must be compatible with future External Secrets Operator/Vault integration
- **Approach:**
  - Zalando creates standard Kubernetes secrets
  - Secrets follow predictable naming pattern
  - External Secrets Operator can sync from Vault later
- **Verification:** Standard K8s secrets compatible with all secret management tools

### NFR-5: Maintainability

- **Requirement:** Solution must reduce operational overhead
- **Metrics:**
  - Eliminate sync script maintenance
  - Reduce manual intervention
  - Declarative configuration
- **Verification:** No custom scripts needed, operator handles everything

### NFR-6: Documentation

- **Requirement:** All changes must be documented
- **Deliverables:**
  - Update `docs/guides/DATABASE.md` with new approach
  - Update `CHANGELOG.md` with changes
  - Document secret name format clearly
  - Add troubleshooting guide for cross-namespace secrets

---

## 5. Out of Scope

The following are explicitly NOT included in this feature:

- ❌ **External Secrets Operator Integration** - Documented in research and Feature.md, implementation planned for future phase
- ❌ **Vault Integration** - Documented in research, implementation planned for future phase
- ❌ **Automatic Password Rotation via ESO** - Procedures documented, full ESO integration in future phase
- ❌ **Backup Implementation** - Configuration documented in research, actual S3/GCS setup in future phase (requires cloud credentials)
- ❌ **Changes to CloudNativePG clusters** - This spec focuses on Zalando operator only
- ❌ **Custom secret name templates** - Using operator default template
- ❌ **Infrastructure roles configuration** - Only manifest roles affected for cross-namespace secrets
- ❌ **Backward compatibility with old secret names** - Old secrets will be deleted
- ❌ **Performance tuning for CloudNativePG** - Separate specification needed for CloudNativePG clusters

---

## 6. Edge Cases & Error Handling

### Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| **Secret already exists in target namespace** | Operator updates existing secret with new password |
| **Old secret still exists in `user` namespace** | Can be safely deleted after new secrets verified |
| **Service pod starts before secret created** | Pod will fail and restart until secret exists (standard K8s behavior) |
| **Operator configuration change fails** | Rollback to previous configuration, keep sync script as backup |
| **Database CRD update fails** | Rollback CRD changes, operator continues with old configuration |
| **Helm values update fails** | Service continues using old secret name (may fail if old secret deleted) |
| **Namespace doesn't exist** | Operator creates secret when namespace is created, or fails gracefully |

### Error Scenarios

| Error | User Message | System Action |
|-------|--------------|---------------|
| **Operator config invalid** | "Invalid operator configuration" | Operator logs error, feature not enabled |
| **Database CRD format invalid** | "Invalid user format in CRD" | Operator logs error, secrets not created |
| **Secret creation fails** | "Failed to create secret in namespace" | Operator retries, logs error |
| **Service can't find secret** | "secret not found" | Pod fails to start, Kubernetes retries |
| **Database connection fails** | "Failed to connect to database" | Service logs error, retries connection |

### Rollback Scenarios

| Scenario | Rollback Action |
|----------|------------------|
| **Operator config causes issues** | Revert operator configuration, disable `enable_cross_namespace_secret` |
| **Services fail after migration** | Restore sync script, revert Helm values to old secret names |
| **Secrets not created correctly** | Manually sync secrets using script, investigate operator logs |

---

## 7. Success Metrics

### Key Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Secret Creation Success Rate** | 100% | Verify secrets exist in correct namespaces after deployment |
| **Service Startup Success Rate** | 100% | Services start without "secret not found" errors |
| **Database Connection Success Rate** | 100% | Services successfully connect to databases |
| **Sync Script Removal** | 100% | Script deleted, no references in codebase |
| **Documentation Completeness** | 100% | All relevant docs updated with new approach |
| **Zero Downtime** | 100% | No service downtime during migration |
| **PostgreSQL Performance** | Cache hit ratio >95% | Monitor pg_stat_database metrics |
| **Password Rotation** | Every 90 days | Track password age, alert on overdue |
| **Backup Success Rate** | 100% | Monitor backup completion, alert on failures |
| **Backup Age** | <24 hours | Alert if last backup >24 hours ago |

### Definition of Done

- [ ] All acceptance criteria met for FR-1 through FR-11
- [ ] Operator configuration updated and verified
- [ ] Database CRD updated with namespace notation
- [ ] Helm values updated for notification and shipping services
- [ ] Secrets created in correct namespaces (notification, shipping)
- [ ] Services successfully access secrets and connect to databases
- [ ] Old secrets cleaned up from `user` namespace
- [ ] Sync script removed (`scripts/04b-sync-supporting-db-secrets.sh`)
- [ ] Sync script invocation removed from `scripts/04-deploy-databases.sh`
- [ ] Documentation updated (`docs/guides/DATABASE.md`)
- [ ] CHANGELOG updated
- [ ] No impact on other clusters (`auth-db`, `review-db`)
- [ ] All edge cases handled
- [ ] Error scenarios tested
- [ ] Rollback plan documented
- [ ] PostgreSQL performance tuning parameters applied and validated
- [ ] Password rotation procedures documented and tested
- [ ] Backup strategy documented (implementation in future phase)

---

## 8. Open Questions

- [ ] **Performance Tuning**: Which clusters should receive performance tuning first? (Recommendation: Start with high-traffic clusters like auth-db)
- [ ] **Password Rotation**: Should we implement native rotation first or wait for ESO integration? (Recommendation: Document native approach, implement ESO in future)
- [ ] **Backup Configuration**: Do we have S3/GCS credentials for backup setup? (Recommendation: Document configuration, implement when credentials available)

---

## 9. Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 2.4 | 2026-01-02 | [CONSOLIDATED] Merged monitoring requirements (spec-monitoring-user.md) into main specification. Added FR-13 (Add PostgreSQL Monitoring with Sidecar Exporter), FR-14 (Create PodMonitor per Cluster), and FR-15 (Verify Sidecar Monitoring). Documented production-ready sidecar approach with per-cluster isolation. | System |
| 2.3 | 2026-01-02 | [UPDATED] Corrected Helm values structure details in FR-1: added specific field name corrections (`cluster_domain` not `cluster_name`, `configAwsOrGcp` not `configBackup`, direct fields in `configConnectionPooler` not nested `default_parameters`), clarified `configPostgresql.parameters` doesn't exist (parameters set in CRDs). Updated technical details and acceptance criteria to match official Helm chart structure. | System |
| 2.2 | 2026-01-01 | [UPDATED] Added Postgres Operator UI component requirement (FR-12). Documented UI deployment, configuration, and access methods. UI provides graphical interface for database cluster management. | System |
| 2.1 | 2025-12-30 | [UPDATED] Added critical Helm values structure fix requirement (FR-1) - root cause of cross-namespace secret issue. Added fallback solution (FR-4) for manual secret YAML files. Added missing `shipping` user requirement for shipping-v2 service (FR-3). Updated verification steps to include all three services. Based on refined research v1.9 and plan Section 12. | System |
| 2.0 | 2025-12-29 | [UPDATED] Expanded specification to include production-ready requirements: PostgreSQL Performance Tuning (FR-7), Password Rotation (FR-8), and Backup Strategy (FR-9). Updated problem statement, user personas, and success metrics. Focused on DevOps/SRE production deployment requirements. | System |
| 1.0 | 2025-12-26 | Initial specification based on research findings (cross-namespace secrets only) | System |

---

## 10. Related Research

**Research Document:** `specs/active/Zalando-operator/research.md`

**Key Findings from Research:**
- ✅ Zalando Postgres Operator v1.15.1 supports `enable_cross_namespace_secret` (confirmed via official documentation)
- ✅ **CRITICAL**: Helm chart requires flat structure (`configKubernetes:`, `configGeneral:`, etc.) as top-level keys, NOT nested under `config:`
- ✅ **Field Name Corrections**: `cluster_domain` (not `cluster_name`), `configAwsOrGcp` (not `configBackup`), direct fields in `configConnectionPooler` (not `default_parameters` nested structure)
- ✅ **configPostgresql.parameters**: Does NOT exist in operator config - PostgreSQL parameters are set per-cluster in CRDs
- ✅ Configuration format: `configKubernetes.enable_cross_namespace_secret: true` in Helm values.yaml (creates OperatorConfiguration CRD)
- ✅ User format: `namespace.username` (dot notation)
- ✅ Secret name format: `{namespace}.{username}.{clustername}.credentials.postgresql.acid.zalan.do`
- ✅ Bugfix #2912 in v1.15.0 fixes secret creation in other namespaces when using preparedDatabases and OwnerReference
- ✅ No impact on other clusters
- ✅ Compatible with future External Secrets Operator/Vault integration
- ✅ **PostgreSQL Performance Tuning**: Comprehensive tuning guide with production-ready examples (memory, WAL, query planner, parallelism, autovacuum, logging)
- ✅ **Password Rotation**: Native Zalando approach and External Secrets Operator integration documented
- ✅ **Backup Strategy**: WAL-E/WAL-G configuration, PITR procedures, disaster recovery planning documented

**Decisions:**
- ✅ APPROVED - Proceed with enabling native cross-namespace secret feature and removing sync script
- ✅ APPROVED - Document PostgreSQL performance tuning parameters for production deployment
- ✅ APPROVED - Document password rotation procedures (native and ESO approaches)
- ✅ APPROVED - Document backup strategy (implementation in future phase when cloud credentials available)

---

## Next Steps

1. ✅ Review specification (this document)
2. Run `/plan Zalando-operator` to create technical implementation plan
3. Run `/tasks Zalando-operator` to break down into executable tasks
4. Implement changes following the plan
5. Verify all acceptance criteria met
6. Update documentation

---

*Specification created with SDD 2.0*
