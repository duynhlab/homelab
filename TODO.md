# Platform Engineering Learning Checklist

A practical checklist for learning DevOps/SRE skills through this project. Items marked with references point to actual implementations in this repo.

---

## Infrastructure & GitOps

- [x] **Kustomize bases/overlays + GitOps deployment** — `kubernetes/base/`, `kubernetes/overlays/`, Flux Kustomizations
- [x] **Flux Operator with OCI sync** — `kubernetes/clusters/local/`, OCI registry at `localhost:5050`
- [x] **CI/CD pipelines for container images** — `.github/workflows/build-*.yml` (backend, frontend, init, k6)
- [x] **Helm chart publishing to OCI registry** — `.github/workflows/helm-release.yml`
- [x] **GHCR multi-level image naming** — `ghcr.io/duynhne/<repo>/<image>:<tag>` for auto-linking packages to repos
- [x] **Shared reusable CI/CD workflows** — `duyhenryer/shared-workflows` (docker-build-go, docker-build, go-check)
- [x] **Dependabot for dependency management** — gomod, github-actions, docker across all 8 service repos
- [x] **CronJobs via HelmRelease** — Migrated raw Jobs to `cronjobs` Helm chart (`oci://ghcr.io/duyhenryer/charts/cronjobs`)
- [x] **Flux validation script** — `scripts/flux-validate.sh` validates clusters, infrastructure kustomizations, and app manifests
- [ ] Automated image tag updates via Flux Image Automation
- [ ] GitOps drift detection and reconciliation monitoring (Flux alerts → Alertmanager)
- [ ] Separate manifest repository for GitOps workflow (mono-repo → multi-repo)
- [ ] Infrastructure as Code with Terraform/Pulumi for cloud resources
- [ ] Canary deployments with Argo Rollouts and traffic analysis
- [ ] Multi-environment promotion (dev → staging → prod)
- [ ] Pre-deploy validation gates (lint → build → test → scan → deploy)

---

## Observability (Metrics, Logs, Traces, Profiles)

- [x] **Prometheus + Grafana dashboards** — `kubernetes/infra/controllers/metrics/`, 14 dashboards in `kubernetes/infra/configs/monitoring/grafana/dashboards/`
- [x] **SLI/SLO monitoring with Sloth** — `kubernetes/infra/configs/monitoring/slo/` (9 PrometheusServiceLevel CRDs)
- [x] **Distributed tracing with Tempo** — `kubernetes/infra/controllers/tracing/tempo/`
- [x] **Logging with Loki + Vector** — `kubernetes/infra/controllers/logging/`
- [x] **Continuous profiling with Pyroscope** — `kubernetes/infra/controllers/profiling/`
- [x] **Jaeger integration** — `kubernetes/infra/controllers/tracing/jaeger/`
- [ ] Alertmanager with routing rules and receivers (currently disabled)
- [ ] Golden signals alerting (Latency, Errors, Traffic, Saturation)
- [ ] Actionable alerts with runbook links (alert → page → runbook → fix)
- [ ] Anomaly detection and synthetic monitoring
- [ ] Exemplars: link metrics → traces in Grafana
- [ ] Log-based alerting (Loki ruler → Alertmanager)

---

## Data Platform & Persistence

- [x] **PostgreSQL with CloudNativePG operator** — `kubernetes/infra/controllers/databases/cloudnativepg-operator.yaml`, clusters: `product-db`, `transaction-shared-db`
- [x] **PostgreSQL with Zalando operator** — `kubernetes/infra/controllers/databases/zalando-operator.yaml`, clusters: `auth-db`, `supporting-shared-db`
- [x] **Connection poolers** — PgBouncer (Zalando sidecar), PgCat (`transaction-shared-db`), PgDog (`product-db`)
- [x] **SQL migrations with Flyway** — `services/*/db/migrations/Dockerfile`, `.github/workflows/build-init.yml`
- [x] **PostgreSQL internals deep-dive** — `docs/databases/postgresql_internals_product_db.md`
- [x] **PostgreSQL internals mastery** — `docs/databases/postgresql_internals_product_db.md`:
  - [x] Buffer pool tuning (shared_buffers, effective_cache_size, work_mem)
  - [x] WAL mechanics (redo logs, checkpoint tuning, wal_level)
  - [x] MVCC behavior (tuple visibility, transaction isolation levels, bloat)
  - [x] Vacuum and autovacuum optimization
- [~] **Connection management and query routing** — `docs/databases/database.md`:
  - [x] Connection pooler deep-dive (PgBouncer vs PgCat vs PgDog trade-offs)
  - [x] Query routing strategies (read/write split, sharding keys)
  - [ ] Connection lifecycle and timeout tuning (pool sizes, idle timeout, statement timeout)
- [~] **Replication strategies** — `docs/databases/replication_strategy.md`:
  - [x] Streaming replication internals (WAL sender/receiver, sync vs async)
  - [ ] Logical replication for selective table sync
  - [ ] Multi-source replication patterns
  - [x] Replication lag monitoring and optimization
- [ ] sqlc code generation + repository pattern
- [~] **PostgreSQL Backup & Recovery Mastery** — `docs/databases/backup.md`:
  - [x] Physical backup architecture (Base backup + WAL archiving) — Implemented via CloudNativePG & Zalando
  - [ ] Point-in-Time Recovery (PITR) strategy (concepts, WAL replay, timeline IDs)
  - [ ] RPO/RTO analysis and trade-offs (storage cost vs recovery time)
  - [ ] Tooling comparison: Barman (CNPG) vs WAL-G (Zalando)
  - [ ] Backup lifecycle & retention policies (S3 versioning, immutable backups)
  - [ ] Disaster Recovery drills:
    - [ ] Perform a full Point-in-Time Recovery (PITR)
    - [ ] Corrupt/delete data and recover to specific transaction
    - [ ] Measure actual RTO during drill
- [~] **PostgreSQL High Availability (HA) Mastery** — `docs/databases/replication_strategy.md`:
  - [x] Patroni under the hood (DCS, Leader Election, loop behavior) — Implemented in both operators
  - [x] Synchronous vs Asynchronous Replication trade-offs (Performance vs Durability) — `transaction-shared-db` (Sync) vs `product-db` (Async)
  - [ ] Split-brain protection mechanisms (Watchdog, Fencing)
  - [ ] Quorum commits consistency tuning (`synchronous_standby_names`)
  - [ ] Failover scenarios & recovery drills:
    - [ ] Manual failover (switchover) practice
    - [ ] Forced failover (kill primary pod) -> Measure downtime
    - [ ] Network partition simulation (simulate split-brain)
  - [ ] Client-side failover handling (libpq `target_session_attrs`, connection retry logic)
- [x] **CloudNativePG extensions management** — `Database` resource for declarative `CREATE EXTENSION`, `shared_preload_libraries` for preload, `extensions.md` guide
- [x] **Database naming conventions** — Single-DB clusters use service name (`auth-db`), multi-DB use `*-shared-db` (`supporting-shared-db`, `transaction-shared-db`)


- [ ] Connection pooler tuning (pool sizes, timeouts, prepared statements)
- [x] **Valkey/Redis caching with TTL policies and operation tracing** — `kubernetes/infra/controllers/caching/valkey/`
- [x] **Read replica routing (PgCat/PgDog query routing)** — Implemented via PgCat/PgDog poolers

---

## Security & Secrets

- [x] **Cosign image signing (backend)** — `.github/workflows/build-be.yml` (keyless signing)
- [ ] Cosign signing for frontend, init, k6 images (parity with backend)
- [x] **External Secrets Operator + HashiCorp Vault** — `kubernetes/infra/controllers/secrets/`, `kubernetes/infra/configs/secrets/`
  - Vault (dev mode) + ESO + ClusterSecretStore
  - Shadow-first migration: DB credentials, backup credentials, pooler credentials
  - Documentation: `docs/secrets/secrets-management.md`
- [ ] SOPS or SealedSecrets for GitOps-safe secrets
- [ ] Secret rotation automation (database credentials, scheduled via CronJob)
- [~] **Supply chain security**:
  - [x] Cosign keyless signing (backend images)
  - [ ] SBOM generation with Syft (attach to container images)
  - [x] Image vulnerability scanning in CI (Trivy/Grype gate) — Enabled for `cart-service` via shared workflow
  - [ ] SLSA provenance attestations (GitHub Actions OIDC)
  - [ ] Immutable image tags (digest pinning)
- [~] **Security hardening**:
  - [ ] Container hardening (non-root, read-only rootfs, distroless/minimal base images)
  - [ ] Pod Security Admission (restricted profile per namespace)
  - [ ] Seccomp/AppArmor profiles for workloads
  - [ ] CIS Kubernetes Benchmark compliance scan (kube-bench)
  - [ ] Vulnerability management pipeline (scan → triage → remediate → verify)
- [ ] Policy-as-code with Kyverno or OPA/Gatekeeper (enforce image policies, labels, resource limits)
- [ ] Network policies for namespace isolation (Calico/Cilium)
- [ ] RBAC least-privilege review (ServiceAccounts, ClusterRoles)
- [ ] Encryption at rest and in transit (TLS for DB connections, mTLS between services)

---

## Application Services

- [x] **Go microservices with 3-layer architecture** — `services/*/` (Web → Logic → Core)
- [x] **API versioning (v1 only)** — `services/*/internal/web/v1/` (v2 removed; shipping-v2 suspended)
- [x] **OpenTelemetry instrumentation** — `services/*/middleware/tracing.go`
- [x] **React frontend with API client** — `frontend/`
- [x] **golangci-lint enforcement** — 60+ linters across all 8 service repos, CI-gated
- [x] **Shared Go package library** — `github.com/duynhne/pkg` (zerolog logger, reusable modules)
- [x] **Developer documentation standards** — AGENTS.md (3-layer coding rules, code quality) + README.md (dev guide) across all repos
- [ ] gRPC services with Protobuf definitions
- [ ] Message queue system (NATS/Kafka/Redis Streams) with workers
- [ ] Rate limiting and API quotas
- [ ] Circuit breakers and retry policies
- [ ] Event-driven architecture with idempotency patterns

---

## Service Mesh & Traffic Management

- [ ] Istio service mesh with mTLS
- [ ] Ingress gateway with TLS termination
- [ ] Traffic shifting (weight-based, header-based routing)
- [ ] Circuit breakers, retries, timeouts at mesh level
- [ ] Fault injection for chaos engineering
- [ ] Service-to-service authentication (SPIFFE/SPIRE)

---

## Reliability & Operations

- [x] **k6 load testing** — `services/k6/`, `.github/workflows/build-k6.yml`
- [x] **Runbooks/troubleshooting docs** — `docs/runbooks/troubleshooting/`
- [ ] Chaos engineering with Litmus or Chaos Mesh
- [~] **Disaster recovery**:
  - [x] Database backup to S3 (barmanObjectStore, WAL-G)
  - [ ] PITR drill (point-in-time recovery end-to-end)
  - [ ] Kubernetes resource backup with Velero
  - [ ] DR runbooks codified and periodically tested
- [ ] Incident response practice (mock incident → postmortem → action items)
- [ ] On-call rotation simulation with PagerDuty/Opsgenie
- [ ] Game days (planned failure scenarios — kill primary, network partition, resource starvation)
- [ ] Capacity planning and resource right-sizing (requests/limits optimization)

---

## Distributed Systems Theory

- [ ] **CAP theorem and trade-offs**:
  - [ ] Consistency vs Availability scenarios (CP vs AP systems)
  - [ ] Real-world examples: PostgreSQL (CP), Cassandra (AP), CockroachDB (CP with tunable)
- [ ] **Consensus protocols**:
  - [ ] Raft protocol (etcd, Consul, CockroachDB)
  - [ ] Paxos fundamentals
  - [ ] Leader election and split-brain prevention
- [ ] **Partition tolerance and failure modes**:
  - [ ] Network partition handling strategies
  - [ ] Quorum-based systems and write consistency
  - [ ] Eventual consistency and conflict resolution (CRDTs, vector clocks)
- [ ] **Distributed transactions**:
  - [ ] Two-phase commit (2PC) and its limitations
  - [ ] Saga pattern for microservices
  - [ ] Outbox pattern for reliable messaging

---

## Platform Engineering & Enablement

- [x] **Standardized CI/CD templates** — `duyhenryer/shared-workflows` (reusable for all repos)
- [x] **Developer onboarding docs** — AGENTS.md, README.md with dev commands in every repo
- [ ] Reference architecture module (scaffold for new microservice: code + Helm + HelmRelease + SLO + migration)
- [ ] Platform self-service (CLI/template to bootstrap new service end-to-end)
- [ ] Design review and PR review checklists
- [ ] Compliance mapping (CIS/NIST controls → pipeline evidence, audit artifacts)

---

## Learning Resources & Interview Prep

- [ ] Document "why" for each technology choice (ADRs)
- [ ] Create architecture decision records in `docs/adr/`
- [ ] Prepare talking points for each completed item
- [ ] Practice explaining trade-offs (e.g., Zalando vs CloudNativePG)

---

**Legend:**
- `[x]` = Done (implemented in this repo)
- `[~]` = Partial (started but incomplete)
- `[ ]` = Pending (to learn/implement)
