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

2. **Research Current State**
   - Read `docs/METRICS.md` for metrics documentation
   - Check `grafana-dashboard.json` for current panels
   - Review `k8s/prometheus/configmap.yaml` for Prometheus config
   - Check SLO rules in `slo/k8s/` if SLO-related

3. **Identify Impact**
   - Dashboard changes: `grafana-dashboard.json`
   - Prometheus changes: `k8s/prometheus/configmap.yaml`
   - Kubernetes changes: `k8s/*/deployment.yaml`, `k8s/*/service.yaml`
   - SLO changes: `slo/k8s/*.yaml`

4. **Create Plan**
   - List specific files to modify
   - Include step-by-step implementation
   - Mention testing requirements
   - Include deployment steps

5. **Ask Questions**
   - Clarify ambiguous requirements
   - Confirm technical approach
   - Verify scope and constraints
