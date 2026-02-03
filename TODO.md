# Platform Engineering Learning Checklist

A practical checklist for learning DevOps/SRE skills through this project. Items marked with references point to actual implementations in this repo.

---

## Infrastructure & GitOps

- [x] **Kustomize bases/overlays + GitOps deployment** — `kubernetes/base/`, `kubernetes/overlays/`, Flux Kustomizations
- [x] **Flux Operator with OCI sync** — `kubernetes/clusters/local/`, OCI registry at `localhost:5050`
- [x] **CI/CD pipelines for container images** — `.github/workflows/build-*.yml` (backend, frontend, init, k6)
- [x] **Helm chart publishing to OCI registry** — `.github/workflows/helm-release.yml`
- [ ] Automated image tag updates via Flux Image Automation
- [ ] Separate manifest repository for GitOps workflow (mono-repo → multi-repo)
- [ ] Infrastructure as Code with Terraform/Pulumi for cloud resources
- [ ] Canary deployments with Argo Rollouts and traffic analysis
- [ ] Multi-environment promotion (dev → staging → prod)

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
- [ ] Anomaly detection and synthetic monitoring
- [ ] Exemplars: link metrics → traces in Grafana

---

## Data Platform & Persistence

- [x] **PostgreSQL with CloudNativePG operator** — `kubernetes/infra/controllers/databases/cloudnativepg-operator.yaml`, clusters: `product-db`, `transaction-db`
- [x] **PostgreSQL with Zalando operator** — `kubernetes/infra/controllers/databases/zalando-operator.yaml`, clusters: `auth-db`, `review-db`, `supporting-db`
- [x] **Connection poolers** — PgBouncer (Zalando sidecar), PgCat (`transaction-db`), PgDog (`product-db`)
- [x] **SQL migrations with Flyway** — `services/*/db/migrations/Dockerfile`, `.github/workflows/build-init.yml`
- [x] **PostgreSQL internals deep-dive** — `docs/databases/postgresql_internals_product_db.md`
- [ ] sqlc code generation + repository pattern
- [ ] Database backup/restore with Barman or pgBackRest
- [ ] Point-in-Time Recovery (PITR) drill
- [ ] HA failover drill (kill primary, verify replica promotion)
- [ ] Connection pooler tuning (pool sizes, timeouts, prepared statements)
- [x] **Valkey/Redis caching with TTL policies and operation tracing** — `kubernetes/infra/controllers/caching/valkey/`
- [x] **Read replica routing (PgCat/PgDog query routing)** — Implemented via PgCat/PgDog poolers

---

## Security & Secrets

- [x] **Cosign image signing (backend)** — `.github/workflows/build-be.yml` (keyless signing)
- [ ] Cosign signing for frontend, init, k6 images (parity)
- [ ] ExternalSecrets Operator + SecretStore (AWS SSM, Vault, etc.)
- [ ] SOPS or SealedSecrets for GitOps-safe secrets
- [ ] Secret rotation automation (database credentials)
- [ ] SBOM generation with Syft + vulnerability scanning with Grype/Trivy
- [ ] SLSA provenance attestations for supply chain security
- [ ] Policy-as-code with Kyverno or OPA/Gatekeeper
- [ ] Network policies for namespace isolation
- [ ] Pod Security Standards (restricted profile)
- [ ] RBAC least-privilege review

---

## Application Services

- [x] **Go microservices with 3-layer architecture** — `services/*/` (Web → Logic → Core)
- [x] **API versioning (v1 only)** — `services/*/internal/web/v1/` (v2 removed; shipping-v2 suspended)
- [x] **OpenTelemetry instrumentation** — `services/*/middleware/tracing.go`
- [x] **React frontend with API client** — `frontend/`
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
- [ ] Disaster recovery automation (backup restore drill)
- [ ] Incident response practice (mock incident → postmortem)
- [ ] On-call rotation simulation with PagerDuty/Opsgenie
- [ ] Game days (planned failure scenarios)
- [ ] Capacity planning and cost optimization

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
