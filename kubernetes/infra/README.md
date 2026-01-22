# Infrastructure Manifests - Controllers/Configs Pattern

This directory contains all infrastructure manifests organized by deployment phase: **controllers** (operators) and **configs** (instances).

## Directory Structure

```
kubernetes/infra/
├── namespaces.yaml                 # All 14 namespaces (deployed first)
├── kustomization.yaml              # Root kustomization
├── controllers/                    # Phase 1: Operators + Helm Charts
│   ├── kustomization.yaml
│   ├── monitoring/
│   │   ├── prometheus-operator.yaml    # kube-prometheus-stack Helm
│   │   ├── grafana-operator.yaml       # Grafana Operator Helm
│   │   └── metrics-server.yaml         # Metrics Server Helm
│   ├── apm/
    │   │   ├── kustomization.yaml
    │   │   ├── loki/                       # Loki (raw manifests)
    │   │   ├── tempo/                      # Tempo (raw manifests)
    │   │   ├── pyroscope/                  # Pyroscope (raw manifests)
    │   │   ├── victorialogs/               # VictoriaLogs (HelmRelease)
    │   │   ├── vector/                     # Vector (HelmRelease)
    │   │   ├── jaeger/                     # Jaeger (HelmRelease)
    │   │   └── otel-collector/             # OTel Collector (HelmRelease)
│   ├── databases/
│   │   ├── zalando-operator.yaml       # Zalando Postgres Operator Helm
│   │   └── cloudnativepg-operator.yaml # CloudNativePG Operator Helm
│   └── slo/
│       └── sloth-operator.yaml         # Sloth Operator Helm
└── configs/                        # Phase 2: Instances + CRs
    ├── kustomization.yaml
    ├── monitoring/
    │   ├── servicemonitors/            # ServiceMonitors
    │   ├── grafana/                    # Grafana CR + Datasources
    │   └── podmonitors/                # PodMonitors for databases
    ├── databases/
    │   ├── secrets/                    # Database secrets
    │   ├── configmaps/                 # Vector configs (for Zalando sidecars), monitoring queries
    │   ├── monitoring/                 # CloudNativePG PodMonitors (deploy AFTER database clusters)
    │   ├── poolers/                    # PgCat HelmReleases
    │   └── instances/                  # PostgreSQL CRs (5 databases)
    └── slo/
        └── crds/                       # PrometheusServiceLevel CRs (9 services)
```

## Architecture Pattern

### Controllers vs Configs Separation

**Controllers** (Infrastructure Layer):
- Helm charts for operators (Prometheus, Grafana, Postgres, Sloth)
- APM components (Loki, Tempo, Pyroscope, Vector, Jaeger, OTel Collector) - infrastructure, not CRDs
- Provide CRDs and manage lifecycle
- Deployed FIRST to ensure CRDs are available

**Configs** (Application Layer):
- Custom Resources (Grafana, PostgreSQL, PrometheusServiceLevel)
- ConfigMaps used by CRDs (e.g., Vector ConfigMaps for Zalando databases)
- Deployed AFTER controllers are ready

This separation ensures:
1. **Correct deployment order** - Operators install CRDs before instances are created
2. **Clear boundaries** - Infrastructure vs application concerns
3. **Easier debugging** - Controllers and configs can be reconciled independently
4. **Matches manual scripts** - Follows `scripts/backup/` deployment pattern

## Deployment Order

```mermaid
flowchart TD
    Controllers[controllers-local] --> Configs[configs-local]
    Configs --> Apps[apps-local]
    
    subgraph Controllers[controllers-local]
        PrometheusOp[Prometheus Operator]
        GrafanaOp[Grafana Operator]
        MetricsServer[Metrics Server]
        ZalandoOp[Zalando Postgres Operator]
        CNPGOp[CloudNativePG Operator]
        SlothOp[Sloth Operator]
        APM[APM: Loki, Tempo, Vector, Jaeger, OTel]
    end
    
    subgraph Configs[configs-local]
        Monitoring[Monitoring Configs: Grafana, ServiceMonitors]
        Databases[Database Configs: instances, poolers, secrets, PodMonitors, Vector ConfigMaps]
        SLO[SLO Configs: PrometheusServiceLevel CRs]
    end
```

**Flux Kustomizations:**
1. `controllers-local` - Deploys namespaces + operators (CRDs)
2. `configs-local` - Deploys all configs (depends on controllers-local)
3. `apps-local` - Deploys microservices (depends on configs-local)

## Key Components

### Monitoring Controllers
- **kube-prometheus-stack** - Prometheus Operator + Prometheus + Alertmanager
- **grafana-operator** - Grafana Operator for managing Grafana instances
- **metrics-server** - Kubernetes metrics API for HPA and kubectl top

### Database Controllers
- **postgres-operator** - Zalando Postgres Operator (manages 3 clusters: auth, review, supporting)
- **cloudnative-pg** - CloudNativePG Operator (manages 2 clusters: product, transaction)

### SLO Controllers
- **sloth** - Sloth Operator for SLO/SLI management

### APM Controllers (Infrastructure)
APM components are deployed under `kubernetes/infra/controllers/apm/`:
- **Loki** - raw manifests (Deployment/ConfigMap/Service)
- **Tempo** - raw manifests (Deployment/ConfigMap/Service)
- **Pyroscope** - raw manifests (Deployment/ConfigMap/Service)
- **VictoriaLogs** - HelmRelease (log storage, collector disabled)
- **Vector** - HelmRelease (DaemonSet, dual-ships to Loki + VictoriaLogs)
- **Jaeger** - HelmRelease
- **OTel Collector** - HelmRelease

**Note**: APM components are infrastructure (not CRDs), so they're in controllers layer.

### Database Monitoring
- **CloudNativePG PodMonitors**: `configs/databases/monitoring/` - Deploy AFTER database clusters (within same kustomization, processed in order)
- **Zalando PodMonitors**: `configs/monitoring/podmonitors/` - Deploy with monitoring configs

### Vector Configuration
- **Vector HelmRelease**: `controllers/apm/vector/` - APM infrastructure component
- **Vector ConfigMaps for Zalando**: `configs/databases/configmaps/vector-configs/` - Used by Zalando CRDs (`acid.zalan.do/v1`) as sidecar configs

## How to Deploy

```bash
# 1. Create Kind cluster + OCI registry
./scripts/kind-up.sh

# 2. Bootstrap Flux Operator
./scripts/flux-up.sh

# 3. Push all manifests to OCI
make flux-push

# 4. Verify reconciliation
flux get kustomizations
```

**Deployment sequence:**
1. Namespaces created
2. Controllers reconcile (operators install CRDs)
3. Configs reconcile (instances created using CRDs)
4. Apps reconcile (microservices start)

## Verification

```bash
# Check controllers
flux get kustomization controllers-local
kubectl get helmreleases --all-namespaces | grep operator

# Check configs
flux get kustomization configs-local
kubectl get postgresql -A
kubectl get cluster -A
kubectl get grafana -A
kubectl get prometheusservicelevel -A

# Check apps
flux get kustomization apps-local
kubectl get pods --all-namespaces
```

## Troubleshooting

### Controllers not ready
```bash
# Check operator logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator
kubectl logs -n postgres-operator -l app.kubernetes.io/name=postgres-operator
kubectl logs -n cloudnative-pg -l app.kubernetes.io/name=cloudnative-pg

# Check operator status
flux get helmreleases --all-namespaces
```

### Configs failing
```bash
# Ensure controllers are ready first
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus-operator -n monitoring --timeout=300s

# Check CRDs are installed
kubectl get crd | grep postgresql
kubectl get crd | grep grafana
kubectl get crd | grep sloth

# Check config status
kubectl describe postgresql auth-db -n auth
kubectl describe grafana grafana -n monitoring
```

## References

- [Flux GitOps Structure](https://fluxcd.io/flux/guides/repository-structure/)
- [Kustomize Documentation](https://kustomize.io/)
- [GitOps Best Practices](https://cloud.google.com/kubernetes-engine/config-sync/docs/concepts/gitops-best-practices)
