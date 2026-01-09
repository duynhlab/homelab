# Flyway Migration Tasks Summary

> **Created**: December 16, 2025  
> **Status**: Ready for Implementation  
> **Related**: [research-flyway-migration.md](./research-flyway-migration.md)

---

## Overview

All Flyway migration Dockerfiles and SQL files have been created. Next steps are to build images, update Helm charts, and test migrations.

---

## ✅ Completed Tasks

### Task 3.3.1: Create Flyway Migration Dockerfiles ✅
- ✅ `services/migrations/auth/Dockerfile`
- ✅ `services/migrations/user/Dockerfile`
- ✅ `services/migrations/product/Dockerfile`
- ✅ `services/migrations/cart/Dockerfile`
- ✅ `services/migrations/order/Dockerfile`
- ✅ `services/migrations/review/Dockerfile`
- ✅ `services/migrations/notification/Dockerfile`
- ✅ `services/migrations/shipping-v2/Dockerfile` ✅ Created

**Dockerfile Pattern:**
```dockerfile
FROM alpine:3.19
RUN apk add --no-cache openjdk17-jre flyway && rm -rf /var/cache/apk/*
RUN mkdir -p /flyway/sql
COPY sql/ /flyway/sql/
WORKDIR /flyway
CMD ["flyway", "migrate"]
```

### Task 3.3.2: Convert Migration Files to Flyway Format ✅
- ✅ Created `sql/` directories for all services
- ✅ Converted `001_init_schema.sql` → `V1__Initial_schema.sql`
- ✅ Removed `IF NOT EXISTS` clauses (Flyway handles idempotency)
- ✅ All 8 services have Flyway-formatted migrations (auth, user, product, cart, order, review, notification, shipping-v2)

**Files Created:**
- `services/migrations/{service}/sql/V1__Initial_schema.sql` (8 files)

---

## ⏳ Remaining Tasks

### Task 3.3.3: Build Migration Images

**Status**: Not Started

**Actions Required:**
1. Update `scripts/05-build-microservices.sh`:
   ```bash
   # Add migration image builds
   for SERVICE in auth user product cart order review notification; do
     MIGRATION_IMAGE="${REGISTRY}/migrations-${SERVICE}:v1"
     echo "Building migration image: ${MIGRATION_IMAGE}"
     docker build -t ${MIGRATION_IMAGE} services/migrations/${SERVICE}/
     docker push ${MIGRATION_IMAGE}
   done
   ```

2. ✅ Create `.github/workflows/build-migration-images.yml`: ✅ Done
   - Builds migration images for 8 services (auth, user, product, cart, order, review, notification, shipping-v2)
   - Triggers on push to v6 branches
   - Changes in `services/migrations/**`

3. Test build locally:
   ```bash
   docker build -t test-migrations-auth services/migrations/auth/
   docker run --rm test-migrations-auth flyway -v
   ```

**Estimated Time**: 1-2 hours (scripts done, testing pending)

---

### Task 3.3.4: Update Helm Chart Templates for Flyway

**Status**: Not Started

**Actions Required:**

1. **Update `charts/templates/deployment.yaml`:**
   - Remove old psql init container code (lines 38-78)
   - Add Flyway init container:
   ```yaml
   {{- if .Values.migrations.enabled }}
   initContainers:
     - name: flyway-migrate
       image: {{ .Values.migrations.image }}
       imagePullPolicy: {{ .Values.migrations.imagePullPolicy | default "IfNotPresent" }}
       env:
         - name: FLYWAY_URL
           value: "jdbc:postgresql://{{ .Values.extraEnv | getDBHost }}:{{ .Values.extraEnv | getDBPort }}/{{ .Values.extraEnv | getDBName }}?sslmode={{ .Values.extraEnv | getDBSSLMode }}"
         - name: FLYWAY_USER
           valueFrom:
             secretKeyRef:
               name: {{ include "microservice.fullname" . }}-db-secret
               key: username
         - name: FLYWAY_PASSWORD
           valueFrom:
             secretKeyRef:
               name: {{ include "microservice.fullname" . }}-db-secret
               key: password
         - name: FLYWAY_LOCATIONS
           value: "filesystem:/flyway/sql"
         - name: FLYWAY_CONNECT_RETRIES
           value: "60"
         - name: FLYWAY_VALIDATE_ON_MIGRATE
           value: "true"
         - name: FLYWAY_BASELINE_ON_MIGRATE
           value: "true"
       command: ["flyway", "migrate"]
   {{- end }}
   ```

2. **Delete `charts/templates/configmap-migrations.yaml`** (not needed)

3. **Update `charts/values.yaml`:**
   ```yaml
   migrations:
     enabled: false
     image: ""  # e.g., ghcr.io/duynhne/migrations-auth:v1
     imagePullPolicy: IfNotPresent
   ```

4. **Update all service values files** (`charts/values/*.yaml`):
   - Remove `migrations.sql` content
   - Add `migrations.image` reference:
   ```yaml
   migrations:
     enabled: true
     image: ghcr.io/duynhne/migrations-auth:v1
   ```

**Files to Modify:**
- `charts/templates/deployment.yaml`
- `charts/templates/configmap-migrations.yaml` (delete)
- `charts/values.yaml`
- `charts/values/auth.yaml`
- `charts/values/user.yaml`
- `charts/values/product.yaml`
- `charts/values/cart.yaml`
- `charts/values/order.yaml`
- `charts/values/review.yaml`
- `charts/values/notification.yaml`

**Estimated Time**: 3-4 hours

---

### Task 3.3.5: Test Flyway Migrations

**Status**: Not Started

**Actions Required:**

1. **Test with one service (auth):**
   ```bash
   # Deploy auth service with Flyway
   helm upgrade --install auth charts/ -f charts/values/auth.yaml -n auth --create-namespace
   
   # Check init container logs
   kubectl logs -n auth deployment/auth -c flyway-migrate
   
   # Verify flyway_schema_history table
   kubectl exec -n postgres-operator -it auth-db-0 -- psql -U postgres -d auth -c "SELECT * FROM flyway_schema_history;"
   
   # Verify tables created
   kubectl exec -n postgres-operator -it auth-db-0 -- psql -U postgres -d auth -c "\dt"
   ```

2. **Test with existing database (baseline):**
   - Deploy to environment with existing schema
   - Verify `FLYWAY_BASELINE_ON_MIGRATE=true` works
   - Check that existing tables are not recreated

3. **Apply to all services:**
   - Deploy all 7 services with Flyway
   - Verify all migrations run successfully
   - Check all `flyway_schema_history` tables

**Estimated Time**: 3-4 hours

---

## Summary

**Completed**: 2/5 subtasks (40%)
- ✅ Dockerfiles created (7 files)
- ✅ Migration files converted (7 files)

**Remaining**: 3/5 subtasks (60%)
- ⏳ Build migration images
- ⏳ Update Helm charts
- ⏳ Test migrations

**Total Estimated Time Remaining**: 7-10 hours

---

## Next Steps

1. **Immediate**: Test Dockerfile builds locally
2. **Next**: Update build script to build migration images
3. **Then**: Update Helm chart templates
4. **Finally**: Test migrations in development environment

---

**Last Updated**: December 16, 2025
