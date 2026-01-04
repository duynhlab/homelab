# Grafana Dashboard Helm Chart

Helm chart for deploying Grafana dashboards with ConfigMap and GrafanaDashboard CRD support. This chart follows the CloudNativePG pattern for single-dashboard charts, ensuring ConfigMap and CRD are always in sync.

## Features

- **Automatic ConfigMap Creation**: Creates ConfigMap from dashboard JSON file automatically
- **GrafanaDashboard CRD Support**: Creates GrafanaDashboard CRD that references the ConfigMap
- **Single Source of Truth**: ConfigMap and CRD are always in sync (no manual synchronization)
- **Large File Support**: Handles large JSON files (~150KB+) without annotation size limit errors
- **Helm Native**: Uses Helm's `.Files.Get` to load dashboard JSON, avoiding kustomization issues
- **Backward Compatible**: Default values match current setup (same ConfigMap/CRD names)
- **OCI Registry Ready**: Can be packaged and published to OCI registries

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Grafana Operator installed and running
- Grafana instance with labels matching `instanceSelector.matchLabels` (default: `dashboards: grafana`)

## Installation

### Basic Installation

```bash
helm install grafana charts/grafana --namespace monitoring
```

### Installation with Custom Values

```bash
helm install grafana charts/grafana \
  --namespace monitoring \
  --set namespace=observability \
  --set grafanaDashboard.folder="Production"
```

### Installation from OCI Registry

```bash
# Install from OCI registry
helm install grafana oci://ghcr.io/duynhne/charts/grafana \
  --version 0.1.0 \
  --namespace monitoring
```

## Helm Template Examples

### Preview Rendered Templates

```bash
# Preview all rendered templates
helm template grafana charts/grafana

# Preview with debug output
helm template grafana charts/grafana --debug
```

### Dry-Run Installation

```bash
# See what would be installed without actually installing
helm install grafana charts/grafana --namespace monitoring --dry-run --debug
```

### Validate Chart

```bash
# Lint chart for errors (recommended)
helm lint charts/grafana

# Validate with custom values
helm lint charts/grafana --set namespace=observability

```

### Template with Custom Values

```bash
# Override values inline
helm template grafana charts/grafana \
  --set namespace=observability \
  --set grafanaDashboard.folder="Production" \
  --set crdName=my-dashboard

# Combine with values file
helm template grafana charts/grafana \
  -f custom-values.yaml \
  --set grafanaDashboard.folder="Custom"
```

## Configuration

See `values.yaml` for all available configuration options. Key parameters:

- `namespace`: Namespace where resources will be created (default: `monitoring`)
- `instanceSelector.matchLabels`: Labels to match Grafana instance (default: `dashboards: grafana`)
- `grafanaDashboard.configMapName`: ConfigMap name (default: `grafana-dashboard-main`)
- `grafanaDashboard.fileName`: Dashboard JSON file name (default: `microservices-dashboard.json`)
- `grafanaDashboard.folder`: Folder in Grafana UI (default: `Observability`)
- `grafanaDashboard.datasources`: Datasource mappings (default: Prometheus)

## Chart Structure

```
charts/grafana/
├── Chart.yaml              # Chart metadata
├── values.yaml              # Default configuration
├── values.schema.json       # JSON schema for values validation
├── README.md                # This file
├── templates/
│   ├── _helpers.tpl         # Template helper functions
│   ├── configmap.yaml       # ConfigMap template
│   └── grafanadashboard.yaml # GrafanaDashboard CRD template
└── files/
    └── microservices-dashboard.json # Dashboard JSON file
```

## Upgrading

```bash
helm upgrade grafana charts/grafana --namespace monitoring
```

## Uninstalling

```bash
helm uninstall grafana --namespace monitoring
```
