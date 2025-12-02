# /plan Command

## Purpose
Analyze requirements and create implementation plan

## Instructions
1. Read relevant docs (METRICS.md, SLO docs, K6 docs)
2. Check current dashboard structure
3. Identify impacted components (dashboard, Prometheus rules, k8s manifests)
4. Create actionable plan with file paths
5. Ask clarifying questions if needed

## Process
1. **Understand Requirements**
   - Read user request carefully
   - Identify what needs to be changed/added
   - Check if similar features exist
   - Consider service-specific namespace context

2. **Research Current State**
   - Read `docs/monitoring/METRICS.md` for metrics documentation
   - Check `grafana-dashboard.json` for current panels (32 panels, UID: `microservices-monitoring-001`)
   - Review `k8s/prometheus/configmap.yaml` for Prometheus config
   - Check SLO definitions in `slo/definitions/` if SLO-related
   - Review service structure: 9 services in separate namespaces

3. **Identify Impact**
   - Dashboard changes: `grafana-dashboard.json`
   - Prometheus changes: `k8s/prometheus/configmap.yaml`
   - Kubernetes changes: `k8s/{service-name}/deployment.yaml`, `k8s/{service-name}/service.yaml`
   - Monitoring changes: `k8s/prometheus/`, `k8s/grafana/`, `k8s/k6/` (all in `monitoring` namespace)
   - SLO changes: `slo/definitions/{service-name}.yaml`
   - Script changes: `scripts/{number}-{purpose}.sh`

4. **Create Plan**
   - List specific files to modify
   - Include step-by-step implementation
   - Mention testing requirements
   - Include deployment steps using numbered scripts
   - Consider service-specific namespace context

5. **Ask Questions**
   - Clarify ambiguous requirements
   - Confirm technical approach
   - Verify scope and constraints
   - Identify which service(s) are affected

## Documentation Structure
- Metrics: `docs/monitoring/METRICS.md`
- Setup: `docs/getting-started/SETUP.md`
- API: `docs/api/API_REFERENCE.md`
- Load Testing: `docs/load-testing/K6_LOAD_TESTING.md`
- SLO: `docs/slo/README.md`, `docs/slo/GETTING_STARTED.md`, etc.

## Namespace Context
- **Service namespaces**: `auth`, `user`, `product`, `cart`, `order`, `review`, `notification`, `shipping`
- **Monitoring namespace**: `monitoring` (Prometheus, Grafana, k6, SLO)

## Scripts Reference
- Infrastructure: `01-create-kind-cluster.sh`, `02-install-metrics.sh`
- Build & Deploy: `05-build-microservices.sh`, `06-deploy-microservices.sh`, `03-deploy-monitoring.sh`, `07-deploy-k6-testing.sh`, `09-setup-access.sh`
- Monitoring: `10-reload-dashboard.sh`
- SLO: `08a-validate-slo.sh`, `08b-generate-slo-rules.sh`, `08-deploy-slo.sh`
- Runbooks: `11-diagnose-latency.sh`, `12-error-budget-alert.sh`
