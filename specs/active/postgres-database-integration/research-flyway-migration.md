# Research: Flyway Migration Integration

> **Research ID**: postgres-database-integration-flyway  
> **Created**: December 14, 2025  
> **Last Updated**: December 14, 2025  
> **Focus**: Research Flyway migration tool to replace current init container SQL approach with proper versioning and migration management

---

## Executive Summary

**Current State**: Database migrations are handled via Kubernetes init containers using `postgres:15-alpine` image that executes a single SQL file (`001_init_schema.sql`) via `psql` command. This approach lacks versioning, migration history tracking, and proper migration management.

**Proposed Solution**: Integrate Flyway 11.19.0 as a migration tool within Kubernetes init containers to provide:
- ✅ Versioned migrations with automatic ordering
- ✅ Migration history tracking (`flyway_schema_history` table)
- ✅ Support for multiple migration files per service
- ✅ Better error handling and validation
- ✅ Migration state management

**Recommendation**: **Adopt Flyway** for better migration management, with a phased migration approach from current single-file to Flyway versioned migrations.

---

## 1. Flyway Overview & Features

### 1.1 What is Flyway?

Flyway is a database migration tool that enables version control for database schemas. It tracks which migrations have been applied and ensures they run in the correct order.

### 1.2 Key Features

**Versioning System:**
- Migrations are versioned using naming convention: `V<Version>__<Description>.sql`
- Examples: `V1__Create_users_table.sql`, `V2__Add_email_column.sql`
- Automatic ordering based on version numbers

**Migration History:**
- Creates `flyway_schema_history` table in database
- Tracks: version, description, type, installed_on, success status
- Provides audit trail of all applied migrations

**Migration Types:**
- **Versioned (V)**: Run once, in order (e.g., `V1__Create_table.sql`)
- **Repeatable (R)**: Run every time if checksum changes (e.g., `R__Update_view.sql`)
- **Undo (U)**: Rollback migrations (commercial edition only)

**Commands:**
- `migrate`: Apply pending migrations
- `info`: Show migration status and history
- `validate`: Validate applied migrations against files
- `repair`: Repair migration history table
- `baseline`: Initialize existing database

### 1.3 Flyway Version Comparison

**Flyway 9 vs Flyway 11.19.0:**

| Feature | Flyway 9 | Flyway 11.19.0 |
|---------|----------|----------------|
| Java Support | Java 8+ | Java 8 & Java 17 (multi-release) |
| Code Analysis | ❌ | ✅ Code Analysis Rules Engine |
| AI Summaries | ❌ | ✅ AI-generated summaries (Desktop) |
| Database Support | Standard | Expanded (Fabric SQL, DB2 ZOS, MariaDB 10.10) |
| New Commands | Basic | `add`, `diff`, `diffApply`, `diffText`, `generate` |
| Check Command | Basic | Enhanced (drift detection, unit testing) |

**Recommendation**: Use **Flyway 11.19.0** for latest features and better PostgreSQL support.

---

## 2. Current Implementation Analysis

### 2.1 Current Architecture

**Init Container Setup:**
```yaml
initContainers:
  - name: migrate
    image: postgres:15-alpine
    command:
      - /bin/sh
      - -c
      - |
        PGPASSWORD="${DB_PASSWORD}" psql \
          -h "${DB_HOST}" \
          -p "${DB_PORT}" \
          -U "${DB_USER}" \
          -d "${DB_NAME}" \
          -f /migrations/001_init_schema.sql
```

**Migration File Structure:**
```
services/migrations/
├── auth/
│   └── 001_init_schema.sql
├── user/
│   └── 001_init_schema.sql
├── product/
│   └── 001_init_schema.sql
...
```

**ConfigMap Structure:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: auth-migrations
data:
  001_init_schema.sql: |
    -- SQL content here
```

### 2.2 Current Limitations

1. **No Versioning**: Single file `001_init_schema.sql` - cannot add new migrations
2. **No History Tracking**: No record of what migrations were applied
3. **Idempotency Only**: Relies on `IF NOT EXISTS` - no migration state management
4. **No Rollback**: Cannot rollback migrations
5. **No Validation**: No checksum validation or migration integrity checks
6. **Manual Management**: Must manually ensure migrations are idempotent

### 2.3 Current Strengths

1. **Simple**: Easy to understand and implement
2. **Lightweight**: Uses standard postgres image
3. **Works**: Current approach functions for initial schema setup
4. **Idempotent**: Uses `IF NOT EXISTS` to prevent errors on re-run

---

## 3. Kubernetes Integration Patterns

### 3.1 Approach Comparison

**Three Main Approaches:**

1. **ConfigMap + Official Flyway Image** (Initial Research)
2. **Custom Migration Image** (Recommended - User Proposal) ⭐
3. **Init Container Copy Pattern** (Not Recommended)

### 3.2 Approach 1: ConfigMap + Official Flyway Image

**Standard Approach:**
```yaml
initContainers:
  - name: flyway-migrate
    image: flyway/flyway:11.19.0
    env:
      - name: FLYWAY_URL
        value: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}
      - name: FLYWAY_USER
        value: ${DB_USER}
      - name: FLYWAY_PASSWORD
        value: ${DB_PASSWORD}
      - name: FLYWAY_LOCATIONS
        value: filesystem:/flyway/sql
    volumeMounts:
      - name: flyway-sql
        mountPath: /flyway/sql
    command: ["flyway", "migrate"]
volumes:
  - name: flyway-sql
    configMap:
      name: auth-flyway-migrations
```

**Pros:**
- ✅ Uses official Flyway image
- ✅ No custom Dockerfile needed
- ✅ Migration files in ConfigMap (easy to update)

**Cons:**
- ❌ Helm chart complexity (ConfigMap management)
- ❌ Migration files in Helm values (large YAML files)
- ❌ ConfigMap size limits (1MB per ConfigMap)
- ❌ Need to manage ConfigMap lifecycle

### 3.3 Approach 2: Custom Migration Image (Recommended) ⭐

**User Proposal: Custom Docker Image with Migration Files Baked In**

**Structure:**
```
services/migrations/
├── auth/
│   ├── Dockerfile
│   └── sql/
│       └── V1__Initial_schema.sql
├── user/
│   ├── Dockerfile
│   └── sql/
│       └── V1__Initial_schema.sql
```

**Option 2A: Using Official Flyway Image (Current)**
```dockerfile
# Use Flyway Alpine image as base (already includes Flyway + Java)
FROM flyway/flyway:11.19.0-alpine

# Copy migration SQL files
COPY sql/ /flyway/sql/

# Default command (can be overridden in Kubernetes)
CMD ["migrate"]
```

**Option 2B: Minimal Alpine + Install Flyway (User Proposal) ⭐⭐**

**Challenge**: Flyway requires Java runtime. Busybox doesn't have Java.

**Solution A: Use Alpine base + install OpenJDK + Flyway manually**
```dockerfile
# Use minimal Alpine base
FROM alpine:3.19

# Install Java (OpenJDK JRE) and wget
RUN apk add --no-cache \
    openjdk17-jre \
    wget \
    && rm -rf /var/cache/apk/*

# Install Flyway manually
ENV FLYWAY_VERSION=11.19.0
ENV FLYWAY_HOME=/opt/flyway
ENV PATH=$FLYWAY_HOME:$PATH

RUN wget -qO- https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}.tar.gz \
    | tar -xz -C /opt \
    && mv /opt/flyway-${FLYWAY_VERSION} ${FLYWAY_HOME} \
    && chmod +x ${FLYWAY_HOME}/flyway

# Create migration directory
RUN mkdir -p /flyway/sql

# Copy migration SQL files
COPY sql/ /flyway/sql/

# Set working directory
WORKDIR /flyway

# Default command
CMD ["flyway", "migrate"]
```

**Solution B: Use Alpine + apk add flyway (Simplest!) ⭐⭐⭐**

**Note**: Cần verify xem package `flyway` có trong Alpine repositories không. Nếu có, đây là cách đơn giản nhất!

```dockerfile
# Use minimal Alpine base
FROM alpine:3.19

# Install Java and Flyway from Alpine repositories
RUN apk add --no-cache \
    openjdk17-jre \
    flyway \
    && rm -rf /var/cache/apk/*

# Create migration directory
RUN mkdir -p /flyway/sql

# Copy migration SQL files
COPY sql/ /flyway/sql/

# Set working directory
WORKDIR /flyway

# Default command
CMD ["flyway", "migrate"]
```

**Nếu `apk add flyway` hoạt động, đây là cách đơn giản nhất!** Chỉ cần 2 dòng install, không cần download hay extract gì cả.

**Image Size Comparison:**
- `flyway/flyway:11.19.0-alpine`: ~150-200MB (includes Flyway + Java)
- `alpine:3.19 + OpenJDK + Flyway`: ~100-150MB (slightly smaller, more control)
- `busybox`: ~1-5MB (but can't run Flyway - no Java)

**Recommendation**: **Option 2B (Alpine + Manual Install)** - gives more control, potentially smaller image, and still simple Helm charts.

**Helm Chart (Simplified):**
```yaml
initContainers:
  - name: flyway-migrate
    image: ghcr.io/duynhne/migrations-auth:v1  # Custom migration image
    env:
      - name: FLYWAY_URL
        value: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}
      - name: FLYWAY_USER
        value: ${DB_USER}
      - name: FLYWAY_PASSWORD
        value: ${DB_PASSWORD}
    command: ["flyway", "migrate"]
```

**Option 2A Pros (Official Flyway Image):**
- ✅ Simple Dockerfile (just COPY)
- ✅ Official image maintained by Flyway team
- ✅ Always up-to-date with latest Flyway version

**Option 2A Cons:**
- ⚠️ Larger image size (~150-200MB)
- ⚠️ Less control over Java/Flyway versions

**Option 2B Pros (Alpine + Install Flyway):** ⭐⭐
- ✅ **Smaller image size** (~100-150MB vs 150-200MB)
- ✅ **More control** over Java and Flyway versions
- ✅ **Customizable** - can optimize further
- ✅ **Much simpler Helm charts** - no ConfigMap needed
- ✅ **Migration files versioned with image** - better traceability
- ✅ **No ConfigMap size limits** - can have many migration files
- ✅ **Cleaner separation** - migrations in Docker image, config in Helm
- ✅ **Easier CI/CD** - build migration images like app images
- ✅ **Better caching** - Docker layer caching for migration files

**Option 2B (apk add flyway) Pros:** ⭐⭐⭐
- ✅ **Simplest Dockerfile** - chỉ cần `apk add flyway`!
- ✅ **No manual download/extract** - Alpine package manager handles it
- ✅ **All benefits of Option 2B** - smaller, simpler Helm charts
- ✅ **Easiest to maintain** - package manager updates

**Option 2B Cons:**
- ⚠️ Need to verify `flyway` package exists in Alpine repos (có thể cần community repo)
- ⚠️ Package version có thể không phải latest (11.19.0)
- ⚠️ Need to build separate migration images
- ⚠️ Need to manage migration image versions

**Recommendation**: 
- **Nếu `apk add flyway` hoạt động**: **Use Approach 2B (apk add flyway)** - đơn giản nhất, không cần build lại image!
- **Nếu không có package**: **Use Approach 2B (Manual Install)** - vẫn nhỏ hơn và đơn giản hơn official image

### 3.4 Approach 3: Init Container Copy Pattern (Not Recommended)

**Pattern:**
```yaml
initContainers:
  - name: copy-migrations
    image: busybox
    command: ['sh', '-c', 'cp /flyway-config/* /flyway/sql/']
    volumeMounts:
      - name: flyway-config
        mountPath: /flyway-config
      - name: migrations
        mountPath: /flyway/sql
  - name: flyway-migrate
    image: flyway/flyway:11.19.0
    volumeMounts:
      - name: migrations
        mountPath: /flyway/sql
```

**Not Recommended**: More complex, requires two init containers, no real benefit over other approaches.

### 3.3 Environment Variable Configuration

**Flyway Environment Variables:**
- `FLYWAY_URL`: JDBC connection string
- `FLYWAY_USER`: Database username
- `FLYWAY_PASSWORD`: Database password
- `FLYWAY_LOCATIONS`: Migration file locations (default: `filesystem:/flyway/sql`)
- `FLYWAY_SCHEMAS`: Target schemas (default: current schema)
- `FLYWAY_BASELINE_ON_MIGRATE`: Baseline existing database (default: false)
- `FLYWAY_VALIDATE_ON_MIGRATE`: Validate migrations (default: true)
- `FLYWAY_CONNECT_RETRIES`: Connection retry attempts (default: 0)

**JDBC URL Format:**
```
jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=${DB_SSLMODE}
```

### 3.4 Multi-Pod Deployment Considerations

**Flyway handles concurrency:**
- Uses database locks to prevent concurrent migrations
- Only one pod can run migrations at a time
- Other pods wait for migration to complete
- Safe for rolling updates

**Best Practice:**
- Use `FLYWAY_CONNECT_RETRIES=60` to wait for database availability
- Use `FLYWAY_VALIDATE_ON_MIGRATE=true` to ensure integrity
- Consider using `FLYWAY_BASELINE_ON_MIGRATE=true` for existing databases

---

## 4. Helm Chart Integration Strategy

### 4.1 Recommended Approach: Custom Migration Images

**Simplified Helm Template: `charts/templates/deployment.yaml`**
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

**No ConfigMap needed!** Migration files are baked into the Docker image.

### 4.2 Helm Values Structure (Simplified)

**Updated `charts/values.yaml`:**
```yaml
# Database migrations (Flyway)
migrations:
  enabled: false
  # Migration image (contains SQL files)
  image: ""  # e.g., ghcr.io/duynhne/migrations-auth:v1
  imagePullPolicy: IfNotPresent
```

**Service-specific values (e.g., `charts/values/auth.yaml`):**
```yaml
migrations:
  enabled: true
  image: ghcr.io/duynhne/migrations-auth:v1
```

**Much simpler!** No large SQL content in Helm values.

### 4.3 Alternative: ConfigMap Approach (Not Recommended)

**If using ConfigMap approach:**
- Need `configmap-flyway-migrations.yaml` template
- Need to store SQL in Helm values
- More complex Helm chart management
- ConfigMap size limits (1MB)

**Recommendation**: Use custom migration images instead.

### 4.3 Environment Variable Extraction

**Challenge**: Current setup uses individual env vars (`DB_HOST`, `DB_PORT`, etc.) instead of single `DATABASE_URL`.

**Solution**: Use Helm template helpers to extract values:
```yaml
{{- define "microservice.db.url" }}
{{- $host := "" }}
{{- $port := "" }}
{{- $name := "" }}
{{- $sslmode := "disable" }}
{{- range .Values.extraEnv }}
{{- if eq .name "DB_HOST" }}{{ $host = .value }}{{ end }}
{{- if eq .name "DB_PORT" }}{{ $port = .value }}{{ end }}
{{- if eq .name "DB_NAME" }}{{ $name = .value }}{{ end }}
{{- if eq .name "DB_SSLMODE" }}{{ $sslmode = .value }}{{ end }}
{{- end }}
jdbc:postgresql://{{ $host }}:{{ $port }}/{{ $name }}?sslmode={{ $sslmode }}
{{- end }}
```

**Alternative**: Use environment variable substitution in Flyway:
```yaml
env:
  - name: FLYWAY_URL
    value: "jdbc:postgresql://$(DB_HOST):$(DB_PORT)/$(DB_NAME)?sslmode=$(DB_SSLMODE)"
  - name: DB_HOST
    valueFrom:
      secretKeyRef:
        name: auth-db-secret
        key: host
```

---

## 5. Migration File Structure Design

### 5.1 Flyway Naming Convention

**Format**: `<Prefix><Version>__<Description>.sql`

**Examples:**
- `V1__Initial_schema.sql` - Version 1, initial schema
- `V2__Add_user_profile.sql` - Version 2, add user profile table
- `V2_1__Add_indexes.sql` - Version 2.1, add indexes
- `R__Update_statistics_view.sql` - Repeatable migration

### 5.2 Proposed File Structure (Custom Image Approach)

**Recommended Structure:**
```
services/migrations/
├── auth/
│   ├── Dockerfile
│   └── sql/
│       └── V1__Initial_schema.sql
├── user/
│   ├── Dockerfile
│   └── sql/
│       └── V1__Initial_schema.sql
├── product/
│   ├── Dockerfile
│   └── sql/
│       ├── V1__Initial_schema.sql
│       └── V2__Add_inventory_table.sql
```

**Each service has:**
- `Dockerfile` - Builds migration image
- `sql/` directory - Contains Flyway migration files

### 5.3 Dockerfile Template

**Standard Dockerfile for each service:**
```dockerfile
# Use Flyway Alpine image (includes Flyway + Java)
FROM flyway/flyway:11.19.0-alpine

# Copy migration SQL files
COPY sql/ /flyway/sql/

# Default command (can be overridden in Kubernetes)
CMD ["migrate"]
```

**Benefits:**
- ✅ Simple and clean
- ✅ Uses official Flyway image
- ✅ Migration files baked into image
- ✅ Version controlled with image tags

### 5.3 Migration Content Changes

**Current (Idempotent):**
```sql
-- Auth Database Schema
-- Idempotent migration script

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    ...
);
```

**Flyway (Versioned):**
```sql
-- V1__Initial_schema.sql
-- Auth Database Schema - Initial Setup

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    ...
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
```

**Key Differences:**
- ❌ Remove `IF NOT EXISTS` (Flyway ensures migrations run once)
- ✅ Add version comment in file
- ✅ Remove idempotency checks (Flyway handles this)
- ✅ Cleaner SQL (no defensive checks needed)

### 5.4 Multi-File Migration Support

**Example: Product Service Evolution**
```
V1__Initial_schema.sql          # Initial tables
V2__Add_inventory_table.sql     # Add inventory
V2_1__Add_product_reviews.sql   # Add reviews FK
V3__Add_full_text_search.sql    # Add search indexes
```

**Helm Values Structure:**
```yaml
migrations:
  enabled: true
  files:
    V1__Initial_schema.sql: |
      -- SQL content
    V2__Add_inventory_table.sql: |
      -- SQL content
    V3__Add_full_text_search.sql: |
      -- SQL content
```

---

## 6. Comparison: Approaches

### 6.1 Feature Comparison

| Feature | Current (psql) | Flyway + ConfigMap | Flyway + Custom Image ⭐ |
|---------|----------------|-------------------|-------------------------|
| **Versioning** | ❌ Single file | ✅ Automatic | ✅ Automatic |
| **History Tracking** | ❌ None | ✅ Yes | ✅ Yes |
| **Multiple Migrations** | ❌ Not supported | ✅ Yes | ✅ Yes |
| **Helm Chart Complexity** | ✅ Simple | ⚠️ Complex (ConfigMap) | ✅ **Simple** |
| **Migration File Management** | ⚠️ In Helm values | ⚠️ In Helm values | ✅ **In Docker image** |
| **ConfigMap Size Limits** | N/A | ⚠️ 1MB limit | ✅ **No limits** |
| **Image Size** | ✅ Small | ⚠️ Large (flyway image) | ⚠️ Large (flyway image) |
| **CI/CD Integration** | ⚠️ Manual | ⚠️ Manual | ✅ **Automated** |
| **Version Control** | ⚠️ Helm values | ⚠️ Helm | ✅ **Docker image tags** |
| **Separation of Concerns** | ⚠️ Mixed | ⚠️ Mixed | ✅ **Clean separation** |

### 6.2 Pros and Cons

**Current Approach (psql):**

**Pros:**
- ✅ Simple and lightweight
- ✅ Uses standard postgres image
- ✅ Easy to understand
- ✅ Works for basic use cases

**Cons:**
- ❌ No versioning system
- ❌ No migration history
- ❌ Cannot add new migrations easily
- ❌ No validation or integrity checks
- ❌ Manual idempotency management
- ❌ Potential race conditions

**Flyway + ConfigMap Approach:**

**Pros:**
- ✅ Proper versioning and ordering
- ✅ Migration history tracking
- ✅ Support for multiple migrations
- ✅ Uses official Flyway image

**Cons:**
- ❌ Complex Helm charts (ConfigMap management)
- ❌ Large Helm values files (SQL content)
- ❌ ConfigMap size limits (1MB)
- ❌ Need to manage ConfigMap lifecycle

**Flyway + Custom Image Approach (Recommended) ⭐:**

**Pros:**
- ✅ **Much simpler Helm charts** - no ConfigMap needed
- ✅ **Migration files versioned with image** - better traceability
- ✅ **No ConfigMap size limits** - can have many migration files
- ✅ **Cleaner separation** - migrations in Docker image, config in Helm
- ✅ **Easier CI/CD** - build migration images like app images
- ✅ **Better caching** - Docker layer caching for migration files
- ✅ **Proper versioning and ordering**
- ✅ **Migration history tracking**
- ✅ **Support for multiple migrations**
- ✅ **Automatic idempotency**
- ✅ **Validation and integrity checks**

**Cons:**
- ⚠️ Need to build separate migration images
- ⚠️ Need to manage migration image versions
- ⚠️ Slightly more complex build process

### 6.3 Recommendation

**Adopt Flyway with Custom Migration Images** because:
1. **Simpler Helm Charts**: No ConfigMap complexity
2. **Better Separation**: Migrations in Docker images, config in Helm
3. **Scalability**: Can add new migrations without restructuring Helm
4. **Version Control**: Migration versions tied to Docker image tags
5. **CI/CD Friendly**: Build migration images like app images
6. **No Size Limits**: ConfigMap has 1MB limit, Docker images don't
7. **Industry Standard**: Flyway is widely used and well-documented
8. **Future-Proof**: Supports complex migration scenarios

---

## 7. Implementation Recommendations

### 7.1 Flyway Version Selection

**Recommendation: Use Flyway 11.19.0**

**Reasons:**
- Latest stable version with enhanced features
- Better PostgreSQL support
- Multi-release Java builds (Java 8 & 17)
- Enhanced validation and code analysis
- Better error messages and diagnostics

**Docker Image**: `flyway/flyway:11.19.0`

### 7.2 Migration Strategy

**Phase 1: Baseline Existing Databases**
- Use `FLYWAY_BASELINE_ON_MIGRATE=true` to initialize existing databases
- Convert `001_init_schema.sql` → `V1__Initial_schema.sql`
- Remove `IF NOT EXISTS` clauses

**Phase 2: Deploy Flyway**
- Update Helm templates
- Deploy with Flyway init containers
- Verify migration history table creation

**Phase 3: Future Migrations**
- Use Flyway versioning for new migrations
- Follow naming convention: `V<Version>__<Description>.sql`

### 7.3 Configuration Best Practices

**Required Flyway Environment Variables:**
```yaml
FLYWAY_URL: jdbc:postgresql://host:port/db?sslmode=disable
FLYWAY_USER: username
FLYWAY_PASSWORD: password
FLYWAY_LOCATIONS: filesystem:/flyway/sql
FLYWAY_CONNECT_RETRIES: 60
FLYWAY_VALIDATE_ON_MIGRATE: true
FLYWAY_BASELINE_ON_MIGRATE: true  # For existing databases
```

**Optional but Recommended:**
```yaml
FLYWAY_SCHEMAS: public
FLYWAY_TABLE: flyway_schema_history
FLYWAY_PLACEHOLDER_REPLACEMENT: true
```

### 7.4 Error Handling

**Flyway Error Scenarios:**
1. **Connection Failure**: Use `FLYWAY_CONNECT_RETRIES=60` to wait for DB
2. **Migration Failure**: Flyway stops, requires manual intervention
3. **Checksum Mismatch**: Use `flyway repair` command
4. **Out of Order**: Flyway prevents this automatically

**Kubernetes Integration:**
- Init container failure prevents pod startup
- Check logs: `kubectl logs <pod> -c flyway-migrate`
- Use `flyway info` to check migration status

---

## 8. Migration Path

### 8.1 Step-by-Step Migration Plan (Custom Image Approach)

**Step 1: Create Migration Dockerfiles**
- Create `services/migrations/{service}/Dockerfile` for each service
- Create `services/migrations/{service}/sql/` directory
- Move and rename: `001_init_schema.sql` → `sql/V1__Initial_schema.sql`
- Remove `IF NOT EXISTS` clauses
- Test SQL syntax

**Step 2: Build Migration Images**
- Build images: `docker build -t ghcr.io/duynhne/migrations-{service}:v1 services/migrations/{service}/`
- Push to registry
- Update build script to include migration images

**Step 3: Update Helm Templates**
- Update `deployment.yaml` with Flyway init container
- Remove ConfigMap template (not needed)
- Update `values.yaml` structure (simplified)

**Step 4: Update Service Values**
- Update all 7 service values files with migration image reference
- Much simpler: just `migrations.image` and `migrations.enabled`

**Step 5: Test in Development**
- Deploy to dev environment
- Verify Flyway migration execution
- Check `flyway_schema_history` table

**Step 6: Deploy to Production**
- Use `FLYWAY_BASELINE_ON_MIGRATE=true` for existing DBs
- Monitor migration execution
- Verify application startup

### 8.2 Build Script Integration

**Update `scripts/05-build-microservices.sh`:**
```bash
# Build migration images
for SERVICE in auth user product cart order review notification; do
  MIGRATION_IMAGE="ghcr.io/duynhne/migrations-${SERVICE}:v1"
  docker build -t ${MIGRATION_IMAGE} services/migrations/${SERVICE}/
  docker push ${MIGRATION_IMAGE}
done
```

### 8.2 Backward Compatibility

**For Existing Databases:**
- Use `FLYWAY_BASELINE_ON_MIGRATE=true` to initialize
- Flyway will create history table and mark V1 as applied
- Future migrations will work normally

**For New Databases:**
- Flyway will run V1 migration normally
- No baseline needed

### 8.3 Rollback Strategy

**If Migration Fails:**
1. Check Flyway logs: `kubectl logs <pod> -c flyway-migrate`
2. Fix migration SQL file
3. Use `flyway repair` if checksum mismatch
4. Redeploy with fixed migration

**If Need to Rollback Application:**
- Flyway migrations are forward-only (community edition)
- Must create new migration to undo changes
- Or restore database from backup

---

## 9. Open Questions

1. **Flyway Image Size**: Is larger image size acceptable? (flyway:11.19.0 vs postgres:15-alpine)
   - **Answer**: Yes, init containers are temporary and image size is acceptable for benefits

2. **Multiple Migration Files**: How to structure multiple migrations in Helm values?
   - **Answer**: Use map structure: `migrations.files: { V1__...: |, V2__...: | }`

3. **Environment Variable Extraction**: Best way to extract DB env vars for Flyway URL?
   - **Answer**: Use Helm template helpers or environment variable substitution

4. **Baseline Strategy**: Should we baseline existing databases or start fresh?
   - **Answer**: Use `FLYWAY_BASELINE_ON_MIGRATE=true` for existing, normal migration for new

5. **Migration File Location**: Keep in `services/migrations/` or move to Helm chart?
   - **Answer**: Keep in `services/migrations/` for source of truth, copy to Helm values

---

## 10. Next Steps

1. **Create Implementation Plan**: Detailed plan for Flyway integration with custom images
2. **Create Migration Dockerfiles**: Create Dockerfile for each service migration
3. **Update Build Script**: Add migration image build to `scripts/05-build-microservices.sh`
4. **Update Helm Templates**: Update `deployment.yaml` with Flyway init container (simplified)
5. **Convert Migration Files**: Rename and update SQL files
6. **Update Service Values**: Add migration image references (simplified)
7. **Test in Development**: Verify Flyway migration execution
8. **Document Migration Process**: Create guide for adding new migrations

## 11. Custom Migration Image Structure

### 11.1 Directory Structure

```
services/migrations/
├── auth/
│   ├── Dockerfile
│   └── sql/
│       └── V1__Initial_schema.sql
├── user/
│   ├── Dockerfile
│   └── sql/
│       └── V1__Initial_schema.sql
├── product/
│   ├── Dockerfile
│   └── sql/
│       ├── V1__Initial_schema.sql
│       └── V2__Add_inventory_table.sql
...
```

### 11.2 Dockerfile Template

**Recommended Dockerfile (`services/migrations/{service}/Dockerfile`):**

**Option 1: Using apk add flyway (Simplest - if package exists)** ⭐⭐⭐
```dockerfile
# Use minimal Alpine base
FROM alpine:3.19

# Install Java and Flyway from Alpine repositories
RUN apk add --no-cache \
    openjdk17-jre \
    flyway \
    && rm -rf /var/cache/apk/*

# Create migration directory
RUN mkdir -p /flyway/sql

# Copy migration SQL files
COPY sql/ /flyway/sql/

# Set working directory
WORKDIR /flyway

# Default command (can be overridden in Kubernetes)
CMD ["flyway", "migrate"]
```

**Option 2: Manual Install (if apk package doesn't exist)**
```dockerfile
# Use minimal Alpine base
FROM alpine:3.19

# Install Java (OpenJDK JRE) and wget
RUN apk add --no-cache \
    openjdk17-jre \
    wget \
    && rm -rf /var/cache/apk/*

# Install Flyway manually
ENV FLYWAY_VERSION=11.19.0
ENV FLYWAY_HOME=/opt/flyway
ENV PATH=$FLYWAY_HOME:$PATH

RUN wget -qO- https://repo1.maven.org/maven2/org/flywaydb/flyway-commandline/${FLYWAY_VERSION}/flyway-commandline-${FLYWAY_VERSION}.tar.gz \
    | tar -xz -C /opt \
    && mv /opt/flyway-${FLYWAY_VERSION} ${FLYWAY_HOME} \
    && chmod +x ${FLYWAY_HOME}/flyway

# Create migration directory
RUN mkdir -p /flyway/sql

# Copy migration SQL files
COPY sql/ /flyway/sql/

# Set working directory
WORKDIR /flyway

# Default command (can be overridden in Kubernetes)
CMD ["flyway", "migrate"]
```

**Alternative: Official Flyway Image (Simpler but Larger)**
```dockerfile
# Use Flyway Alpine image (includes Flyway + Java)
FROM flyway/flyway:11.19.0-alpine

# Copy migration SQL files
COPY sql/ /flyway/sql/

# Default command (can be overridden in Kubernetes)
CMD ["migrate"]
```

### 11.3 Build Command

```bash
# Build migration image for a service
docker build -t ghcr.io/duynhne/migrations-auth:v1 services/migrations/auth/

# Push to registry
docker push ghcr.io/duynhne/migrations-auth:v1
```

### 11.4 Helm Values Example

**`charts/values/auth.yaml`:**
```yaml
migrations:
  enabled: true
  image: ghcr.io/duynhne/migrations-auth:v1
```

**That's it!** Much simpler than ConfigMap approach.

---

## References

- [Flyway Documentation](https://flywaydb.org/documentation/)
- [Flyway Docker Hub](https://hub.docker.com/r/flyway/flyway)
- [Flyway Kubernetes Best Practices](https://blog.sebastian-daschner.com/entries/flyway-migrate-databases-managed-k8s)
- [Flyway Naming Conventions](https://flywaydb.org/documentation/concepts/migrations#naming)

---

**Last Updated**: December 14, 2025
