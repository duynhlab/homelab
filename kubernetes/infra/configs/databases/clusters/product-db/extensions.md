# Product-db 

## EXTENSION CLASSIFICATION:
### HOW TO DETERMINE: Which extension needs preload?
Rule of thumb:
1. ***Monitoring/Logging extensions***: Usually require preload  
`pgaudit`, `pg_stat_statements`, `auto_explain`, `pg_qualstats`
2. ***Storage engines***: Usually require preload  
`timescaledb`, `citus`, `zombodb`
3. ***Replication extensions***: Usually require preload  
`pglogical`, `wal2json`
4. ***Utility functions***: DO NOT require preload  
`pgcrypto`, `uuid-ossp`, `hstore`, `postgis_fdw`

### Type 1: Only CREATE EXTENSION needed (No preload required)
```yaml
# Database-only extensions (50+ extensions)
extensions:
  - name: pgcrypto      # Cryptographic functions
  - name: uuid-ossp     # UUID generation
  - name: hstore        # Key-value store
  - name: unaccent      # Text search without accents
  - name: tablefunc     # Crosstab functions
  - name: earthdistance # Distance calculations
  - name: fuzzystrmatch # Fuzzy string matching
```
Why no `preload` is needed:
- Only provides SQL functions
- Does not interfere with PostgreSQL internals
- Acts more like a plugin than a core module

### Type 2: Requires both PRELOAD and CREATE EXTENSION

```yaml
# Cluster level: Preload
shared_preload_libraries:
  - pgaudit              # Audit logging
  - pg_stat_statements   # Query statistics
  - auto_explain         # Auto EXPLAIN
  - timescaledb          # Time-series database
  - pglogical            # Logical replication

# Database level: Create
extensions:
  - name: pgaudit
  - name: pg_stat_statements
  - name: timescaledb
```

Why both are needed:
- `Preload`: Loads the `C` library into the PostgreSQL process
- `CREATE EXTENSION`: Creates SQL objects inside the database

### Custom Image

```dockerfile
# Dockerfile.custom-extensions
FROM ghcr.io/cloudnative-pg/postgresql:16.4-system-bookworm

# Install extensions from apt repository
RUN apt-get update && \
    apt-get install -y \
    postgresql-16-pglogical \
    postgresql-16-postgis-3 \
    postgresql-16-pg-qualstats \
    postgresql-16-pg-stat-kcache \
    postgresql-16-hypopg \
    postgresql-16-plpython3 \
    && rm -rf /var/lib/apt/lists/*

# Install from source (if package not available)
RUN git clone https://github.com/citusdata/pg_cron.git && \
    cd pg_cron && \
    make && \
    make install && \
    cd .. && rm -rf pg_cron
```

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: custom-ext-db
spec:
  instances: 3
  imageName: your-registry/custom-postgres:16.4-extended
  
  postgresql:
    # No need for extensions section as they are installed in the image
    shared_preload_libraries:
      - pglogical
      - pg_stat_kcache
      - pg_qualstats
      - pg_cron
    
    parameters:
      shared_preload_libraries: "pglogical,pg_stat_kcache,pg_qualstats,pg_cron"
      pg_cron.database_name: "appdb"
```

### Mix Built-in and External
```yaml
# Production Database with monitoring + analytics
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: production-db
  namespace: production
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:16.4-system-bookworm
  
  # MONITORING SECTION
  monitoring:
    enablePodMonitor: true
    customQueriesConfigMap:
      name: postgres-metrics
  
  postgresql:
    # External extensions for monitoring
    extensions:
      - name: pgaudit
        image:
          reference: ghcr.io/cloudnative-pg/pgaudit:1.7.0-16-bookworm
      - name: pg_stat_kcache
        image:
          reference: ghcr.io/cloudnative-pg/pg_stat_kcache:2.4.0-16-bookworm
      - name: pg_qualstats
        image:
          reference: ghcr.io/cloudnative-pg/pg_qualstats:2.0.7-16-bookworm
      - name: pg_wait_sampling
        image:
          reference: ghcr.io/cloudnative-pg/pg_wait_sampling:1.1.7-16-bookworm
    
    shared_preload_libraries:
      - pgaudit
      - pg_stat_statements  # Built-in
      - pg_stat_kcache      # External
      - pg_qualstats        # External
      - pg_wait_sampling    # External
    
    parameters:
      # External extensions config
      pgaudit.log: "ddl, write"
      pg_stat_statements.track: "all"
      pg_stat_kcache.track: "top"
      pg_qualstats.enabled: "true"
      
      # Resource optimization for extensions
      shared_preload_libraries: "pgaudit,pg_stat_statements,pg_stat_kcache,pg_qualstats,pg_wait_sampling"
      max_connections: "200"
      shared_buffers: "4GB"
      
  # Backup extensions
  backup:
    barmanObjectStore:
      destinationPath: "s3://backups"
    recoveryTarget:
      targetTLI: "latest"
---
# Application Database
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: app-database
  namespace: production
spec:
  name: appdb
  owner: appuser
  cluster:
    name: production-db
  
  extensions:
    # Monitoring extensions
    - name: pgaudit
    - name: pg_stat_statements
    - name: pg_stat_kcache
    - name: pg_qualstats
    - name: pg_wait_sampling
    
    # Application extensions
    - name: pgcrypto
    - name: uuid-ossp
    - name: citext
    - name: btree_gin
    
    # Optional: GIS if needed
    # - name: postgis
```

### Verify in Cluster
```sh
# 1. Check which extensions are LOADED (shared_preload_libraries)
kubectl exec -it product-db-1 -n product -- \
  psql -U postgres -c "SHOW shared_preload_libraries;"
# Output: pgaudit,pg_stat_statements,auto_explain

# 2. Check which extensions are CREATED in the database
kubectl exec -it product-db-1 -n product -- \
  psql -U postgres -d product -c "\dx"
# Output: pgaudit, pg_stat_statements, pgcrypto, uuid-ossp, ...

# 3. Check extension files
kubectl exec -it product-db-1 -n product -- \
  ls -la /usr/lib/postgresql/18/lib/
# pgaudit.so, pg_stat_statements.so, ...

# 4. Check which extension needs preload
kubectl exec -it product-db-1 -n product -- \
  psql -U postgres -c "SELECT name FROM pg_available_extensions WHERE name IN ('pgaudit', 'pg_stat_statements', 'pgcrypto') AND installed_version IS NOT NULL;"
```
