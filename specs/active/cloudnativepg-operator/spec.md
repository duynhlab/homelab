# Specification: CloudNativePG Production-Ready Configuration

**Task ID:** cloudnativepg-operator
**Created:** 2025-12-29
**Status:** Ready for Planning
**Version:** 1.2
**Last Updated:** 2026-01-02

---

## 1. Problem Statement

### The Problem

The current CloudNativePG database clusters (transaction-db and product-db) are configured for learning/development purposes and lack production-ready features:

1. **High Availability Gap**: Transaction-DB cluster runs with only 2 instances (1 primary + 1 replica), which provides minimal redundancy. A single node failure could impact availability.

2. **Data Loss Risk**: Without logical replication slot synchronization, CDC clients (Debezium, Kafka Connect) would lose data during failover scenarios, making the cluster unsuitable for event-driven architectures.

3. **Performance Issues**: Current PostgreSQL parameters are tuned for small workloads (256MB shared_buffers, minimal parallelism), which will not scale for production transaction workloads (cart + order services).

4. **Operational Blindness**: No monitoring integration exists for CloudNativePG clusters, making it impossible to detect issues, track performance, or set up alerts for production operations.

### Current Situation

- **Transaction-DB**: 2 instances, basic parameters, no monitoring
- **Product-DB**: 2 instances, basic parameters, no monitoring
- **Secrets**: Manual creation via kubectl (now migrated to YAML files - DONE)
- **Monitoring**: Only Zalando operator clusters have PodMonitors configured

### Desired Outcome

Production-ready CloudNativePG clusters with:
- **High Availability**: 3-node HA cluster with automatic failover (< 30 seconds)
- **Zero Data Loss**: Synchronous replication with logical replication slot sync for CDC support
- **Optimal Performance**: Production-tuned PostgreSQL parameters for transaction workloads
- **Full Observability**: Prometheus monitoring for all CloudNativePG clusters with metrics collection

---

## 2. User Personas

### Primary User: DevOps/SRE Engineer

- **Who:** Operations team responsible for database reliability and performance
- **Goals:** 
  - Ensure database high availability and zero data loss
  - Monitor cluster health and performance
  - Detect and respond to issues proactively
  - Optimize database performance for production workloads
- **Pain points:** 
  - No visibility into CloudNativePG cluster health
  - Risk of data loss during failover
  - Performance bottlenecks with current tuning
  - Manual failover recovery
- **Tech comfort:** High - Kubernetes, PostgreSQL, observability tools

### Secondary User: Application Developer

- **Who:** Developers building cart and order services
- **Goals:**
  - Reliable database connections
  - Fast query performance
  - No data loss during transactions
- **Pain points:**
  - Slow queries due to suboptimal tuning
  - Connection issues during failover
  - Data inconsistency concerns
- **Tech comfort:** Medium - Application development, database usage

### Tertiary User: Platform/Infrastructure Engineer

- **Who:** Infrastructure team managing Kubernetes cluster
- **Goals:**
  - Declarative configuration management
  - Standardized monitoring across all databases
  - Production-ready patterns
- **Pain points:**
  - Inconsistent monitoring setup
  - Manual configuration management
  - Lack of production-ready patterns
- **Tech comfort:** High - Kubernetes operators, GitOps

---

## 3. Functional Requirements

### FR-1: High Availability Configuration (3 Nodes)

**Description:** Upgrade transaction-db cluster from 2 to 3 instances with synchronous replication for zero data loss and improved availability.

**User Story:**
> As a DevOps engineer, I want the transaction-db cluster to run with 3 instances (1 primary + 2 replicas) with synchronous replication so that the cluster can survive a single node failure without data loss and provide read scaling capabilities.

**Acceptance Criteria:**
- [ ] Transaction-DB cluster runs with exactly 3 instances (1 primary + 2 replicas)
- [ ] Synchronous replication is configured with `dataDurability: required` for zero data loss
- [ ] At least 1 synchronous replica is required before commit (`number: 1`)
- [ ] Automatic failover occurs within 30 seconds when primary fails
- [ ] Cluster maintains quorum during failover (no split-brain scenarios)
- [ ] Read operations can be distributed across 2 replicas for load balancing
- [ ] Pod Disruption Budgets are automatically created by operator
- [ ] `syncReplicaElectionConstraint` is commented out (not needed for current setup)
- [ ] Configuration is stored in `k8s/postgres-operator-cloudnativepg/crds/transaction-db.yaml`

**Priority:** Must Have

**Technical Details:**
- File: `k8s/postgres-operator-cloudnativepg/crds/transaction-db.yaml`
- Current: `instances: 2`
- Target: `instances: 3`
- Synchronous replication: `method: any`, `number: 1`, `dataDurability: required`
- `syncReplicaElectionConstraint`: Commented out (not needed for current setup)
- Storage class: Use `standard` or comment out if `fast-ssd` not available
- `syncReplicaElectionConstraint`: Commented out (not needed for current setup)
- Storage class: Use `standard` or comment out if `fast-ssd` not available

---

### FR-2: Logical Replication Slot Synchronization

**Description:** Enable logical replication slot synchronization across all nodes in HA cluster to prevent data loss for CDC clients during failover.

**User Story:**
> As a DevOps engineer, I want logical replication slots to be automatically synchronized across all nodes in the HA cluster so that CDC clients (Debezium, Kafka Connect) do not lose data during failover scenarios.

**Acceptance Criteria:**
- [ ] Logical replication slot synchronization is enabled via `replicationSlots.highAvailability.synchronizeLogicalDecoding: true`
- [ ] WAL level is set to `logical` for logical replication support
- [ ] `hot_standby_feedback: on` is configured to help with replication lag
- [ ] Logical replication slots are automatically replicated to all standby nodes
- [ ] Slots remain valid and accessible after failover
- [ ] CDC clients (Debezium, Kafka Connect) can continue without data loss after failover
- [ ] Configuration is implemented together with HA configuration (FR-1)

**Priority:** Must Have (Required for HA with CDC support)

**Technical Details:**
- Must be implemented together with FR-1 (HA configuration)
- Configuration: `replicationSlots.highAvailability.synchronizeLogicalDecoding: true`
- PostgreSQL parameters: `wal_level: 'logical'`, `hot_standby_feedback: 'on'`

---

### FR-3: Production Performance Tuning

**Description:** Apply production-ready PostgreSQL parameters optimized for transaction workloads (cart + order services).

**User Story:**
> As a DevOps engineer, I want the transaction-db cluster to use production-optimized PostgreSQL parameters so that cart and order services can handle high transaction volumes with optimal performance.

**Acceptance Criteria:**
- [ ] Memory parameters are optimized for 2Gi pod memory (reduced from 4Gi):
  - `shared_buffers: "512MB"` (25% of 2GB memory, adjusted for reduced limits)
  - `effective_cache_size: "1.5GB"` (75% of 2GB memory, adjusted for reduced limits)
  - `maintenance_work_mem: "512MB"`
  - `work_mem: "32MB"`
- [ ] WAL parameters are optimized for high-write workloads:
  - `wal_level: "logical"` (required for logical replication)
  - `min_wal_size: "2GB"`
  - `max_wal_size: "8GB"`
  - `checkpoint_completion_target: "0.9"`
  - `checkpoint_timeout: "15min"`
- [ ] Query planner is optimized for SSD storage:
  - `random_page_cost: "1.1"` (SSD optimization)
  - `effective_io_concurrency: "200"` (SSD optimization)
  - `default_statistics_target: "100"`
- [ ] Parallelism is enabled for multi-core performance:
  - `max_worker_processes: "8"`
  - `max_parallel_workers_per_gather: "4"`
  - `max_parallel_workers: "8"`
  - `max_parallel_maintenance_workers: "4"`
- [ ] Autovacuum is tuned for high-write workloads:
  - `autovacuum_max_workers: "3"`
  - `autovacuum_vacuum_scale_factor: "0.1"`
  - `autovacuum_analyze_scale_factor: "0.05"`
  - `autovacuum_vacuum_cost_delay: "10ms"`
  - `autovacuum_vacuum_cost_limit: "200"`
- [ ] Comprehensive logging is enabled for production debugging:
  - `log_statement: "mod"` (DDL + DML)
  - `log_min_duration_statement: "1000"` (slow queries >1s)
  - `log_checkpoints: "on"`
  - `log_lock_waits: "on"`
  - `log_temp_files: "0"`
  - `log_autovacuum_min_duration: "1000"`
  - `log_connections: "on"`
  - `log_disconnections: "on"`
  - `logging_collector: "on"`
- [ ] Security: `password_encryption: "scram-sha-256"`
- [ ] Resource limits are updated for production workloads (reduced from initial plan):
  - Memory: requests `1Gi`, limits `2Gi` (reduced from 2Gi/4Gi)
  - CPU: requests `500m`, limits `1000m` (reduced from 1000m/2000m)
- [ ] Storage is configured for production: `size: 100Gi`, `storageClass: standard` (or comment out if `fast-ssd` not available)
- [ ] All parameters are applied to transaction-db cluster only

**Priority:** Must Have

**Technical Details:**
- File: `k8s/postgres-operator-cloudnativepg/crds/transaction-db.yaml`
- Update `spec.postgresql.parameters` section
- Update `spec.resources` section (reduced limits: 1Gi/2Gi memory, 500m/1000m CPU)
- Update `spec.storage` section (use `standard` storage class, comment out `fast-ssd` requirement)

---

### FR-4: Monitoring Integration (Manual PodMonitor)

**Description:** Create manual PodMonitor resources for all CloudNativePG clusters. The `enablePodMonitor: true` feature is deprecated and will be removed in future CloudNativePG versions. Manual PodMonitor creation is the recommended approach per official CloudNativePG documentation.

**User Story:**
> As a DevOps engineer, I want to manually create and manage PodMonitor resources for all CloudNativePG clusters so that I have complete control over monitoring configuration, ensuring production-ready setup that won't be affected by future operator changes.

**Acceptance Criteria:**
- [ ] Manual PodMonitor is created for transaction-db cluster:
  - File: `k8s/prometheus/podmonitors/podmonitor-transaction-db.yaml`
  - Namespace: `cart`
  - Selector: `cnpg.io/cluster: transaction-db` (required label)
  - Port: `metrics` (9187)
  - Pod target labels: `cnpg.io/cluster`, `cnpg.io/instanceRole`, `cnpg.io/instanceName`
- [ ] Manual PodMonitor is created for product-db cluster:
  - File: `k8s/prometheus/podmonitors/podmonitor-product-db.yaml`
  - Namespace: `product`
  - Selector: `cnpg.io/cluster: product-db` (required label)
  - Port: `metrics` (9187)
  - Pod target labels: `cnpg.io/cluster`, `cnpg.io/instanceRole`, `cnpg.io/instanceName`
- [ ] `enablePodMonitor: true` is NOT used (deprecated feature):
  - Cluster CRD: `k8s/postgres-operator/cloudnativepg/crds/transaction-db.yaml` - No `monitoring.enablePodMonitor` section
  - Cluster CRD: `k8s/postgres-operator/cloudnativepg/crds/product-db.yaml` - No `monitoring.enablePodMonitor` section
- [ ] Prometheus Operator automatically discovers manual PodMonitors
- [ ] Key metrics are available in Prometheus:
  - `cnpg_collector_up` (cluster availability)
  - `pg_stat_database_*` (database statistics)
  - `pg_stat_activity_*` (active connections)
  - `pg_replication_*` (replication lag)
  - `cnpg_collector_backup_*` (backup status)
  - `cnpg_collector_replication_slots_*` (replication slot status)
- [ ] Metrics are queryable in Prometheus UI
- [ ] Metrics follow CloudNativePG label conventions (`cnpg.io/*`)
- [ ] PodMonitors are version-controlled and can be customized independently

**Priority:** Must Have

**Technical Details:**
- ⚠️ **IMPORTANT**: `spec.monitoring.enablePodMonitor: true` is **DEPRECATED** and will be removed in future CloudNativePG versions
- Create manual PodMonitor CRDs following official CloudNativePG documentation pattern
- Use `cnpg.io/cluster: <cluster-name>` label in selector (required)
- Port name: `metrics` (maps to port 9187)
- Full control over scrape intervals, timeouts, and relabeling
- Reference: [CloudNativePG Monitoring Documentation](https://cloudnative-pg.io/docs/1.28/monitoring)

---

### FR-5: Grafana Dashboard Installation (Grafana Operator)

**Description:** Install official CloudNativePG Grafana dashboard using Grafana Operator approach, matching the existing Grafana setup in the project.

**User Story:**
> As a DevOps engineer, I want the official CloudNativePG Grafana dashboard installed via Grafana Operator so that I can visualize cluster metrics, replication lag, connection pools, and performance data in a standardized dashboard format.

**Acceptance Criteria:**
- [ ] CloudNativePG dashboard JSON is downloaded:
  - Source: `https://raw.githubusercontent.com/cloudnative-pg/grafana-dashboards/main/charts/cluster/grafana-dashboard.json`
  - File: `k8s/grafana-operator/dashboards/cnpg-cluster-dashboard.yaml`
- [ ] GrafanaDashboard CRD is created:
  - File: `k8s/grafana-operator/dashboards/cnpg-cluster-dashboard.yaml`
  - Namespace: `monitoring`
  - Labels: `app: grafana` (matches existing Grafana Operator setup)
  - Format: Grafana Operator CRD format (not Helm chart)
- [ ] Dashboard is automatically discovered by Grafana Operator
- [ ] Dashboard appears in Grafana UI
- [ ] Dashboard displays metrics for all CloudNativePG clusters:
  - Transaction-DB cluster metrics
  - Product-DB cluster metrics
  - Cluster overview (up/down status, instance count)
  - Replication lag visualization
  - Connection pool metrics
  - Query performance data
  - Disk usage information
  - Backup status
  - Replication slots status
- [ ] Prometheus data source is correctly configured in dashboard
- [ ] Dashboard panels show real-time data from Prometheus

**Priority:** Must Have

**Technical Details:**
- Use Grafana Operator approach (Option 4 from research document)
- Download JSON from CloudNativePG GitHub repository
- Create GrafanaDashboard CRD in `k8s/grafana-operator/dashboards/`
- Matches existing Grafana setup (Grafana Operator, not Helm chart)
- No Helm chart dependencies required

---

## 4. Non-Functional Requirements

### NFR-1: High Availability

- **Failover Time**: Automatic failover must complete within 30 seconds
- **Data Durability**: Zero data loss with synchronous replication (`dataDurability: required`)
- **Availability Target**: 99.9% uptime (allows for planned maintenance)
- **Quorum Protection**: Cluster must maintain quorum to prevent split-brain scenarios
- **Read Scaling**: Read operations can be distributed across 2 replicas

### NFR-2: Performance

- **Query Performance**: Production tuning must improve query performance for transaction workloads
- **Connection Handling**: Support up to 200 concurrent connections
- **Parallel Query Execution**: Enable parallel queries for multi-core performance
- **WAL Management**: Optimize WAL size for high-write workloads (8GB max_wal_size)
- **Resource Efficiency**: Use reduced resource limits (1Gi/2Gi memory, 500m/1000m CPU) for cost optimization

### NFR-3: Observability

- **Metrics Collection**: All CloudNativePG clusters must expose metrics to Prometheus
- **Scrape Interval**: Metrics scraped every 15 seconds
- **Metric Availability**: Key metrics available within 1 minute of cluster deployment
- **Label Consistency**: Metrics use CloudNativePG label conventions (`cnpg.io/*`)

### NFR-4: Reliability

- **Configuration Management**: All configurations stored in Git (declarative)
- **Rollback Capability**: Can rollback to previous configuration if issues occur
- **Zero Downtime**: HA configuration changes should not cause downtime
- **Data Safety**: Logical replication slots must survive failover without data loss

### NFR-5: Security

- **Password Encryption**: Use `scram-sha-256` for password encryption
- **Connection Logging**: Log all connections and disconnections for audit
- **Secret Management**: Secrets stored in YAML files (acceptable for personal projects)

### NFR-6: Maintainability

- **Documentation**: All configurations must be documented in research document
- **Consistency**: Follow existing patterns in codebase
- **Version Control**: All changes tracked in Git

---

## 5. Out of Scope

The following are explicitly NOT included in this feature:

- ❌ **Grafana Dashboards (Helm Chart)** - Helm chart installation is out of scope (using Grafana Operator instead)
- ❌ **Alert Rules** - Alert configuration is deferred to future work (monitoring setup only in this phase)
- ❌ **Backup Strategy** - WAL archiving, scheduled backups, PITR are deferred to future work
- ❌ **External Secrets Operator** - Centralized secret management is deferred to future work
- ❌ **Product-DB HA Upgrade** - Only transaction-db gets HA upgrade (product-db stays at 2 instances)
- ❌ **Product-DB Tuning** - Only transaction-db gets production tuning (product-db keeps current config)
- ❌ **Replica Clusters** - Cross-cluster replication is deferred to future work
- ❌ **Declarative Extensions** - PostgreSQL extension management is deferred to future work
- ❌ **Hibernation/Fencing** - Advanced cluster management features are deferred to future work
- ❌ **Custom TLS Certificates** - TLS certificate management is deferred to future work
- ❌ **Volume Snapshots** - Backup via volume snapshots is deferred to future work

---

## 6. Edge Cases & Error Handling

### Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Primary node fails during high write load | Automatic failover to standby within 30 seconds, synchronous replica ensures zero data loss |
| Network partition between nodes | Cluster maintains quorum, prevents split-brain, continues serving from majority partition |
| All replicas fail simultaneously | Cluster enters degraded state, operator attempts recovery, alerts triggered |
| Logical replication slot already exists | Operator manages slot synchronization, no conflicts |
| Prometheus Operator not installed | PodMonitor creation fails gracefully, manual deployment possible |
| Storage class `fast-ssd` not available | Use default `standard` storage class, comment out requirement |
| Node labels not available for anti-affinity | Comment out `syncReplicaElectionConstraint`, not needed for current setup |
| Resource limits exceeded | Kubernetes scheduler prevents pod creation, operator reports error |
| PostgreSQL parameter invalid | Operator rejects configuration, cluster remains in current state |

### Error Scenarios

| Error | User Message | System Action |
|-------|--------------|---------------|
| HA upgrade fails | "Failed to upgrade transaction-db to 3 instances. Check operator logs." | Cluster remains at 2 instances, operator logs error |
| Synchronous replica not available | "Synchronous replica not ready. Writes may be blocked." | Primary blocks writes until synchronous replica available |
| Logical replication slot sync fails | "Failed to synchronize logical replication slots. CDC clients may lose data." | Operator logs error, continues with slot management |
| PodMonitor creation fails | "Failed to create PodMonitor. Metrics may not be collected." | Manual creation possible, Prometheus continues without metrics |
| Prometheus scraping fails | "Prometheus unable to scrape metrics from cluster." | Metrics unavailable, but cluster continues operating |
| Performance tuning causes issues | "PostgreSQL parameters may cause performance degradation." | Rollback to previous configuration, document issue |

---

## 7. Success Metrics

### Key Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Failover Time** | < 30 seconds | Measure time from primary failure to new primary election |
| **Data Loss** | Zero data loss | Verify all committed transactions present after failover |
| **Cluster Availability** | 99.9% uptime | Monitor `cnpg_collector_up` metric over time |
| **Replication Lag** | < 1 second | Monitor `pg_replication_lag` metric |
| **Query Performance** | Improved vs baseline | Compare query duration before/after tuning |
| **Metrics Collection** | 100% of clusters | Verify PodMonitors exist and Prometheus scrapes successfully |
| **Connection Pool Usage** | < 90% of max | Monitor `pg_stat_activity_count / pg_settings_max_connections` |
| **Logical Replication Slot Status** | All slots synchronized | Monitor `cnpg_collector_replication_slots_*` metrics |

### Definition of Done

- [ ] All acceptance criteria met for FR-1 (HA Configuration)
- [ ] All acceptance criteria met for FR-2 (Logical Replication Slot Sync)
- [ ] All acceptance criteria met for FR-3 (Production Tuning)
- [ ] All acceptance criteria met for FR-4 (Built-in PodMonitor)
- [ ] All acceptance criteria met for FR-5 (Grafana Dashboard)
- [ ] Failover tested and verified (< 30 seconds)
- [ ] Zero data loss verified during failover test
- [ ] Metrics visible in Prometheus for both clusters
- [ ] Performance benchmarks show improvement
- [ ] Configuration files committed to Git
- [ ] Documentation updated in research document
- [ ] No critical errors in operator logs
- [ ] All edge cases handled gracefully

---

## 8. Open Questions

- [x] **Storage Class**: Is `fast-ssd` storage class available in the cluster? If not, should we use default storage class?
  - **RESOLVED**: Comment out storage class requirement. Use default storage class if `fast-ssd` not available.
- [x] **Node Labels**: Are node labels (`topology.kubernetes.io/zone`) available for anti-affinity? If not, should we disable `syncReplicaElectionConstraint`?
  - **RESOLVED**: Comment out `syncReplicaElectionConstraint` configuration. Not needed for current setup.
- [x] **Resource Limits**: Are 4Gi memory and 2 CPU cores sufficient for production workloads? Should we adjust based on actual usage?
  - **RESOLVED**: Reduce resource limits - smaller configuration acceptable. Adjust to: Memory requests `1Gi`/limits `2Gi`, CPU requests `500m`/limits `1000m`.
- [x] **Monitoring Alerts**: Should we create alert rules in this phase, or defer to future work?
  - **RESOLVED**: Defer to future work. Only PodMonitor configuration in this phase.
- [x] **Grafana Dashboards**: Should we create basic dashboards, or is metrics collection sufficient?
  - **RESOLVED**: Install official CloudNativePG dashboard using Grafana Operator (matches existing setup). Use built-in PodMonitor instead of manual creation.
- [ ] **Testing Strategy**: Should we perform failover testing in production-like environment before deploying?
  - **PENDING**: Testing approach to be determined during implementation.

---

## 9. Dependencies

### Prerequisites

- ✅ CloudNativePG Operator installed and running
- ✅ Prometheus Operator installed and running
- ✅ Kubernetes cluster with sufficient resources (3 nodes for HA)
- ✅ YAML secret files created (DONE - FR-0)

### External Dependencies

- **CloudNativePG Operator**: Version 1.28+ (supports logical replication slot sync)
- **PostgreSQL**: Version 15+ (supports logical replication)
- **Prometheus Operator**: For PodMonitor CRD support
- **Kubernetes**: Version 1.24+ (for PodDisruptionBudget support)

### Internal Dependencies

- **Transaction-DB Cluster**: Must exist and be operational
- **Product-DB Cluster**: Must exist for monitoring integration
- **Deployment Script**: `scripts/04-deploy-databases.sh` (for applying configurations)

---

## 10. Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.2 | 2026-01-02 | [REFINED] Updated FR-4: Changed from built-in PodMonitor to manual PodMonitor approach. `enablePodMonitor: true` is deprecated per official CloudNativePG documentation | System |
| 1.1 | 2026-01-02 | [REFINED] Updated FR-4 to use built-in PodMonitor, added FR-5 for Grafana dashboard installation | System |
| 1.0 | 2025-12-29 | Initial specification | System |

## 11. Revision History (Legacy)

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.1 | 2026-01-02 | Updated FR-4 to use built-in PodMonitor (`enablePodMonitor: true`), added FR-5 for Grafana dashboard via Grafana Operator, removed manual PodMonitor requirement | AI Agent |
| 1.0 | 2025-12-29 | Initial specification based on research document | AI Agent |

---

## Next Steps

1. ✅ Review specification with stakeholders
2. ✅ Resolve [5] open questions (1 pending: Testing Strategy)
3. Run `/plan cloudnativepg-operator` to create technical implementation plan
4. Run `/tasks cloudnativepg-operator` to break down into executable tasks
5. Begin implementation after plan approval

**Resolved Decisions:**
- **Storage class**: Use `standard`, comment out `fast-ssd` requirement
- **Node labels**: Comment out `syncReplicaElectionConstraint` (not needed)
- **Resource limits**: Reduced to 1Gi/2Gi memory, 500m/1000m CPU
- **Monitoring alerts**: Deferred to future work
- **PodMonitor approach**: Use manual PodMonitor CRDs (official recommended approach, `enablePodMonitor: true` is deprecated)
- **Grafana dashboard**: Use Grafana Operator approach (matches existing setup, no Helm dependencies)

---

*Specification created with SDD 2.0*
