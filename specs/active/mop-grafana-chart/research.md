# Research: MOP Grafana Dashboard Helm Chart with CRD Support

**Task ID:** mop-grafana-chart
**Date:** 2026-01-04
**Status:** Complete
**Version:** 1.2

---

## Executive Summary

This research investigates creating a Helm chart for Microservices Observability Platform (MOP) Grafana dashboards that supports both ConfigMap creation and GrafanaDashboard CRD generation. The chart will manage the microservices-dashboard.json initially and can be extended for additional dashboards. The solution will follow the CloudNativePG Grafana dashboard chart pattern but add CRD support that the official chart currently lacks.

**Key Finding**: CloudNativePG chart only creates ConfigMap (for sidecar discovery), but we need both ConfigMap and GrafanaDashboard CRD (for Grafana Operator). We can create a custom Helm chart that generates both resources, solving the manual CRD creation problem.

**Current Chart Structure**: `charts/` is currently a single chart named "microservice" for deploying Go microservices.

**Target Structure**: 
- `charts/mop/` - Current chart moved and renamed (for microservices deployment)
- `charts/grafana/` - New chart for Grafana dashboard management

**Two separate Helm charts:**
1. **MOP Chart** (`charts/mop/`) - Existing microservices deployment chart (moved from `charts/` root)
2. **Grafana Chart** (`charts/grafana/`) - New chart for managing microservices-dashboard.json

**Chart Dependency Research**: Investigate if `charts/mop/Chart.yaml` can declare `charts/grafana/` as a dependency for coordinated deployment.

---

## Codebase Analysis

### Current Dashboard Management

**Location:** `k8s/grafana-operator/dashboards/`

**Current Pattern:**
1. **JSON Files**: Dashboard definitions stored as JSON files
   - `microservices-dashboard.json` (2843 lines, ~150KB)
   - `pgcat.json` (2124 lines, ~100KB)
   - `tempo-observability-dashboard.json`
   - Other dashboard JSON files

2. **ConfigMaps**: Created via kustomization `configMapGenerator`
   ```yaml
   configMapGenerator:
     - name: grafana-dashboard-main
       files:
         - microservices-dashboard.json
     - name: grafana-dashboard-pgcat
       files:
         - pgcat.json
   ```

3. **GrafanaDashboard CRDs**: Created manually as YAML files
   ```yaml
   apiVersion: grafana.integreatly.org/v1beta1
   kind: GrafanaDashboard
   metadata:
     name: microservices-monitoring
   spec:
     configMapRef:
       name: grafana-dashboard-main
       key: microservices-dashboard.json
   ```

**Current Issues:**
- Manual CRD creation for each dashboard
- ConfigMap and CRD must be kept in sync manually
- No single source of truth (Helm chart would solve this)
- Large JSON files cause ConfigMap annotation size limits (solved by Helm chart)

### Existing Helm Chart Patterns

**Location:** `charts/`

**Current Chart Structure:**
```
charts/
├── Chart.yaml          # Chart metadata (name: "microservice")
├── values.yaml         # Default values
├── templates/          # Kubernetes resource templates
│   ├── _helpers.tpl    # Template helpers
│   ├── deployment.yaml
│   └── service.yaml
└── values/              # Service-specific values
    ├── auth.yaml
    ├── cart.yaml
    └── ...
```

**Note:** This is currently a single chart at the root of `charts/` directory. It will be moved to `charts/mop/` and renamed to "mop" for microservices deployment.

**Template Helper Pattern:**
```go
{{- define "microservice.name" -}}
{{- .Values.name | default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
```

**Key Observations:**
- Charts use `_helpers.tpl` for reusable template functions
- Values can be overridden per service in `values/` directory
- Templates follow standard Helm patterns

### CloudNativePG Chart Analysis

**Reference Chart:** `cnpg-grafana/cluster`

**Template Structure:**
```yaml
# charts/cluster/templates/sidecar-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.grafanaDashboard.configMapName }}
  namespace: {{ default .Release.Namespace .Values.grafanaDashboard.namespace }}
  labels:
    {{ .Values.grafanaDashboard.sidecarLabel }}: {{ .Values.grafanaDashboard.sidecarLabelValue | quote }}
data:
  cnp.json: |-
{{ .Files.Get "grafana-dashboard.json" | indent 6 }}
```

**Key Features:**
- Uses `.Files.Get` to read dashboard JSON from chart files
- Configurable ConfigMap name and namespace
- Supports labels for sidecar discovery
- **Missing**: GrafanaDashboard CRD template

**Values Schema:**
```json
{
  "grafanaDashboard": {
    "configMapName": "string",
    "namespace": "string",
    "labels": {},
    "annotations": {},
    "sidecarLabel": "string",  // deprecated
    "sidecarLabelValue": "string"  // deprecated
  }
}
```

---

## External Solutions

### Option 1: Single Dashboard Chart (CloudNativePG Pattern) - RECOMMENDED

**What it is:** One chart per dashboard, similar to CloudNativePG's approach.

**How it works:**
- Chart contains single dashboard JSON file
- Creates one ConfigMap
- Creates one GrafanaDashboard CRD (solving CloudNativePG limitation)
- Simple structure, follows proven pattern

**Structure:**
```
charts/
├── mop/                    # Microservices deployment chart (moved from root)
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── templates/
│   └── values/
└── grafana/                # Grafana dashboard chart (new)
    ├── Chart.yaml
    ├── values.yaml
    ├── values.schema.json
    ├── README.md
    ├── templates/
    │   ├── _helpers.tpl
    │   ├── configmap.yaml
    │   └── grafanadashboard.yaml
    └── files/
        └── microservices-dashboard.json
```

**Pros:**
- ✅ Simple structure
- ✅ Easy to version per dashboard
- ✅ Independent updates
- ✅ Matches CloudNativePG pattern
- ✅ Can be extended later (add charts/grafana-pgcat/ for pgcat.json)
- ✅ Clear separation of concerns

**Cons:**
- ⚠️ Multiple chart installations needed (but can use dependencies)
- ⚠️ More charts to maintain (but simpler per chart)

**Implementation Complexity:** Low
**Team familiarity:** High (similar to existing charts)
**Fit for our use case:** ⭐⭐⭐ High - Best fit, follows CloudNativePG pattern

### Option 2: Multi-Dashboard Chart

**What it is:** Single chart that manages multiple dashboards via values configuration.

**How it works:**
- Chart contains multiple dashboard JSON files
- Values define which dashboards to enable
- Templates loop through enabled dashboards
- Creates ConfigMap + CRD for each enabled dashboard

**Structure:**
```
charts/grafana/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── configmap.yaml          # Loops through dashboards
│   └── grafanadashboard.yaml   # Loops through dashboards
└── files/
    ├── microservices-dashboard.json
    ├── pgcat.json
    └── [future dashboards]
```

**Values Structure:**
```yaml
dashboards:
  microservices:
    enabled: true
    folder: "Observability"
    configMapName: "grafana-dashboard-main"
    fileName: "microservices-dashboard.json"
    datasources:
      - inputName: DS_PROMETHEUS
        datasourceName: Prometheus
  pgcat:
    enabled: true
    folder: "Databases"
    configMapName: "grafana-dashboard-pgcat"
    fileName: "pgcat.json"
    datasources:
      - inputName: DS_PROMETHEUS
        datasourceName: Prometheus
```

**Template Pattern:**
```yaml
{{- range $name, $dashboard := .Values.dashboards }}
{{- if $dashboard.enabled }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $dashboard.configMapName }}
  namespace: {{ $.Release.Namespace }}
data:
  {{ $dashboard.fileName }}: |-
{{ $.Files.Get (printf "files/%s" $dashboard.fileName) | indent 4 }}
---
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: {{ $name }}
  namespace: {{ $.Release.Namespace }}
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana
  folder: {{ $dashboard.folder | quote }}
  configMapRef:
    name: {{ $dashboard.configMapName }}
    key: {{ $dashboard.fileName }}
  datasources:
    {{- toYaml $dashboard.datasources | nindent 4 }}
{{- end }}
{{- end }}
```

**Pros:**
- ✅ Single chart for all dashboards
- ✅ Unified configuration
- ✅ Easy to add new dashboards (just add JSON + values)
- ✅ Single Helm install/upgrade command
- ✅ Supports both ConfigMap and CRD

**Cons:**
- ⚠️ Slightly more complex template logic
- ⚠️ All dashboards in one chart (but can be disabled)

**Implementation Complexity:** Medium
**Team familiarity:** Medium (requires Helm template loops)
**Fit for our use case:** ⭐⭐ Medium - Works but more complex than needed initially

### Option 3: Chart with Subcharts (Dependencies)

**What it is:** Main chart with dashboard subcharts as dependencies.

**How it works:**
- Main chart: `charts/grafana/` (or `charts/mop/` with grafana dependency)
- Subcharts: `charts/grafana-microservices/`, `charts/grafana-pgcat/`
- Each subchart manages one dashboard
- Main chart coordinates installation

**Structure:**
```
charts/
├── mop/                    # Main chart
│   ├── Chart.yaml          # May declare grafana dependency
│   └── ...
└── grafana/                # Main grafana chart
    ├── Chart.yaml          # Declares subchart dependencies
    └── ...

charts/grafana-microservices/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── configmap.yaml
    └── grafanadashboard.yaml

charts/grafana-pgcat/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── configmap.yaml
    └── grafanadashboard.yaml
```

**Chart.yaml Dependencies:**
```yaml
dependencies:
  - name: grafana-microservices
    version: "0.1.0"
    repository: "file://../grafana-microservices"
    condition: dashboards.microservices.enabled
  - name: grafana-pgcat
    version: "0.1.0"
    repository: "file://../grafana-pgcat"
    condition: dashboards.pgcat.enabled
```

**Pros:**
- ✅ Modular structure
- ✅ Independent dashboard versioning
- ✅ Reusable dashboard charts
- ✅ Can publish subcharts separately

**Cons:**
- ⚠️ More complex structure
- ⚠️ Requires dependency management
- ⚠️ More files to maintain
- ⚠️ Overkill for current needs

**Implementation Complexity:** High
**Team familiarity:** Low (subcharts are advanced)
**Fit for our use case:** Low - Too complex for current requirements

---

## Helm Chart Dependencies Research

### Can MOP Chart Depend on Grafana Chart?

**Question:** Can `charts/mop/Chart.yaml` declare `charts/grafana/` as a dependency?

**Helm Chart Dependencies:**
Helm supports chart dependencies via `Chart.yaml` dependencies section. Dependencies can be:
- Local charts (file:// path)
- Remote charts (OCI registry, Helm repository)
- Git repositories

**Local Chart Dependency Pattern:**
```yaml
# charts/mop/Chart.yaml
dependencies:
  - name: grafana
    version: "0.1.0"
    repository: "file://../grafana"
    condition: grafana.enabled
```

**Deployment Process:**
```bash
# Option A: With dependency
cd charts/mop
helm dependency update
helm install mop . --set grafana.enabled=true

# Option B: Separate installation
helm install grafana ./charts/grafana
helm install mop ./charts/mop
```

**Pros of Dependency Approach:**
- ✅ Single `helm install` command installs both charts
- ✅ Coordinated deployment
- ✅ Can conditionally enable/disable grafana chart
- ✅ Values can be passed from parent to dependency
- ✅ Ensures grafana chart is installed before mop chart

**Cons of Dependency Approach:**
- ⚠️ Requires `helm dependency update` before install
- ⚠️ Dependency must be packaged or available locally
- ⚠️ Version management for dependencies
- ⚠️ Less flexible (must install together)

**Pros of Separate Installation:**
- ✅ More flexible
- ✅ Independent versioning
- ✅ Can install separately
- ✅ No dependency update step

**Cons of Separate Installation:**
- ⚠️ Two install commands
- ⚠️ Manual coordination
- ⚠️ No automatic ordering

**Recommendation:** 
- Research both approaches
- Document dependency pattern if feasible
- Consider deployment script that handles both options
- Start with separate installation for simplicity, add dependency later if needed

---

## Technical Implementation Details

### GrafanaDashboard CRD Template Pattern

**Required Fields:**
```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: {{ dashboard name }}
  namespace: {{ namespace }}
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana  # Must match Grafana instance labels
  folder: {{ folder name }}
  configMapRef:
    name: {{ ConfigMap name }}
    key: {{ JSON file key }}
  datasources:
    - inputName: DS_PROMETHEUS
      datasourceName: Prometheus
```

**Template Example:**
```yaml
{{- range $name, $dashboard := .Values.dashboards }}
{{- if $dashboard.enabled }}
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: {{ $name }}
  namespace: {{ $.Values.namespace | default $.Release.Namespace }}
  {{- with $.Values.commonLabels }}
  labels:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  instanceSelector:
    matchLabels:
      {{- $.Values.instanceSelector.matchLabels | toYaml | nindent 6 }}
  folder: {{ $dashboard.folder | quote }}
  configMapRef:
    name: {{ $dashboard.configMapName }}
    key: {{ $dashboard.fileName }}
  {{- if $dashboard.datasources }}
  datasources:
    {{- toYaml $dashboard.datasources | nindent 4 }}
  {{- end }}
---
{{- end }}
{{- end }}
```

### ConfigMap Template Pattern

**Template Example:**
```yaml
{{- range $name, $dashboard := .Values.dashboards }}
{{- if $dashboard.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $dashboard.configMapName }}
  namespace: {{ $.Values.namespace | default $.Release.Namespace }}
  {{- if or $.Values.commonLabels $dashboard.labels }}
  labels:
    {{- with $.Values.commonLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- with $dashboard.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
  {{- if or $.Values.commonAnnotations $dashboard.annotations }}
  annotations:
    {{- with $.Values.commonAnnotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- with $dashboard.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
data:
  {{ $dashboard.fileName }}: |-
{{ $.Files.Get (printf "files/%s" $dashboard.fileName) | indent 4 }}
---
{{- end }}
{{- end }}
```

### OCI Registry Support

**Helm OCI Commands:**
```bash
# Package chart
helm package charts/grafana

# Push to OCI registry
helm push charts/grafana-0.1.0.tgz oci://ghcr.io/duynhne/helm-charts

# Install from OCI
helm install grafana oci://ghcr.io/duynhne/helm-charts/grafana --version 0.1.0
```

**Chart.yaml Requirements:**
```yaml
apiVersion: v2
name: grafana
description: Microservices Observability Platform Grafana Dashboards
type: application
version: 0.1.0
appVersion: "1.0.0"
maintainers:
  - name: duynhne
    url: https://github.com/duynhne
keywords:
  - grafana
  - dashboard
  - monitoring
  - observability
```

**OCI Registry Benefits:**
- ✅ Version control for charts
- ✅ Easy distribution
- ✅ CI/CD integration
- ✅ No need for Helm repository server

---

## Comparison Matrix

| Criteria | Single Dashboard Chart | Multi-Dashboard Chart | Subcharts |
|----------|------------------------|----------------------|-----------|
| **Setup Complexity** | ⭐ Low | ⭐⭐ Medium | ⭐⭐⭐ High |
| **Maintenance** | ⭐⭐ Medium (multiple charts) | ⭐⭐⭐ Low (single chart) | ⭐ Medium (coordinated) |
| **Flexibility** | ⭐⭐⭐ High (independent) | ⭐⭐⭐ High (per-dashboard config) | ⭐⭐⭐ High (modular) |
| **CRD Support** | ✅ Yes | ✅ Yes | ✅ Yes |
| **ConfigMap Support** | ✅ Yes | ✅ Yes | ✅ Yes |
| **OCI Registry** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Team Familiarity** | ⭐⭐⭐ High | ⭐⭐ Medium | ⭐ Low |
| **Fit for Use Case** | ⭐⭐⭐ **High** | ⭐⭐ Medium | ⭐ Low |

---

## Recommendations

### Primary Recommendation: Single Dashboard Chart (CloudNativePG Pattern)

**Option: Single Dashboard Chart (`charts/grafana/`)**

**Rationale:**
- ✅ Follows CloudNativePG chart pattern (proven approach)
- ✅ Simple structure (one chart per dashboard)
- ✅ Independent versioning per dashboard
- ✅ Easy to extend (add new chart for pgcat later: `charts/grafana-pgcat/`)
- ✅ Supports both ConfigMap and CRD (solving CloudNativePG limitation)
- ✅ Matches project structure (charts/ for all charts)
- ✅ Clear separation: mop chart for microservices, grafana chart for dashboards

**Implementation Structure:**
```
charts/
├── mop/                    # Microservices deployment chart (moved from root)
│   ├── Chart.yaml          # May include grafana dependency
│   ├── values.yaml
│   ├── templates/
│   └── values/
│       ├── auth.yaml
│       └── ...
└── grafana/                # Grafana dashboard chart (new)
    ├── Chart.yaml
    ├── values.yaml
    ├── values.schema.json
    ├── README.md
    ├── templates/
    │   ├── _helpers.tpl
    │   ├── configmap.yaml
    │   └── grafanadashboard.yaml
    └── files/
        └── microservices-dashboard.json
```

**Key Features:**
1. **ConfigMap Creation**: Template creates ConfigMap for microservices-dashboard.json
2. **CRD Creation**: Template creates GrafanaDashboard CRD that references the ConfigMap
3. **File Management**: Dashboard JSON file stored in `files/` directory, loaded via `.Files.Get`
4. **Configuration**: Dashboard settings (folder, datasources, labels) in values.yaml
5. **OCI Support**: Chart can be packaged and pushed to OCI registry
6. **Chart Dependency**: MOP chart can optionally depend on grafana chart

**Values.yaml Structure:**
```yaml
# Namespace for all resources
namespace: monitoring

# Grafana instance selector (must match Grafana CRD labels)
instanceSelector:
  matchLabels:
    dashboards: grafana

# Dashboard configuration
grafanaDashboard:
  # ConfigMap name
  configMapName: "grafana-dashboard-main"
  # Dashboard JSON file name (in files/ directory)
  fileName: "microservices-dashboard.json"
  # Grafana folder name
  folder: "Observability"
  # Datasource mappings
  datasources:
    - inputName: DS_PROMETHEUS
      datasourceName: Prometheus
  # Labels for ConfigMap (for sidecar discovery if needed)
  labels:
    grafana_dashboard: "1"
  # Annotations for ConfigMap
  annotations: {}
```

**Template Implementation:**
- Use `.Files.Get` to load JSON file from `files/` directory
- Use `indent` function to properly format JSON in ConfigMap
- Create both ConfigMap and GrafanaDashboard CRD (not in a loop, single dashboard)

**Benefits:**
- ✅ Solves CloudNativePG limitation (adds CRD support)
- ✅ Single source of truth (Helm chart)
- ✅ Easy updates (`helm upgrade`)
- ✅ Version controlled (Git + OCI registry)
- ✅ Simple structure (no loops needed)
- ✅ Can be extended (add `charts/grafana-pgcat/` for pgcat.json later)

### Chart Dependency Option

**Option A: MOP Chart Depends on Grafana Chart**

**Implementation:**
```yaml
# charts/mop/Chart.yaml
dependencies:
  - name: grafana
    version: "0.1.0"
    repository: "file://../grafana"
    condition: grafana.enabled
```

**Deployment:**
```bash
cd charts/mop
helm dependency update
helm install mop . --set grafana.enabled=true
```

**Pros:**
- Single install command
- Coordinated deployment
- Can disable grafana if needed

**Cons:**
- Requires dependency update step
- Less flexible (must install together)

**Option B: Separate Chart Installation**

**Deployment:**
```bash
helm install grafana ./charts/grafana
helm install mop ./charts/mop
```

**Pros:**
- More flexible
- Independent versioning
- Can install separately

**Cons:**
- Two install commands
- Manual coordination

**Recommendation:** 
- Research both approaches
- Document dependency pattern
- Consider deployment script that supports both
- Start with separate installation for simplicity

---

## Implementation Considerations

### File Size Limits

**Issue:** Large JSON files (150KB+) can cause ConfigMap annotation size limits when using `kubectl apply`.

**Solution:** Helm chart uses `.Files.Get` and creates ConfigMap directly (not via kustomization), avoiding annotation issues.

**Verification:** CloudNativePG chart successfully handles 281KB dashboard JSON.

### Template Complexity

**Challenge:** Looping through dashboards and creating multiple resources.

**Solution:** Use Helm's `range` function with conditional `enabled` flag:
```yaml
{{- range $name, $dashboard := .Values.dashboards }}
{{- if $dashboard.enabled }}
# Create ConfigMap
# Create GrafanaDashboard CRD
{{- end }}
{{- end }}
```

### OCI Registry Publishing

**Process:**
1. Package chart: `helm package charts/grafana`
2. Push to OCI: `helm push charts/grafana-0.1.0.tgz oci://ghcr.io/duynhne/helm-charts`
3. Install: `helm install grafana oci://ghcr.io/duynhne/helm-charts/grafana`

**Benefits:**
- Version control
- Easy distribution
- CI/CD integration

### Backward Compatibility

**Migration Path:**
1. Create Helm chart with existing dashboards
2. Test chart installation
3. Update deployment scripts to use Helm chart
4. Remove manual ConfigMap/CRD files (keep in git history)
5. Update documentation

**No Breaking Changes:** Chart creates same ConfigMap names and CRD names as current setup.

---

## Open Questions

1. **Dashboard Versioning**: Should each dashboard have its own version, or chart version applies to all?
   - **Recommendation**: Chart version applies to all (simpler), but can add per-dashboard version metadata if needed

2. **Additional Dashboards**: Which other dashboards should be included initially?
   - **Current**: microservices, pgcat
   - **Future**: tempo, vector, slo-overview, slo-detailed (if JSON files available)

3. **Chart Dependencies**: Should MOP chart depend on Grafana chart?
   - **Recommendation**: Research both options (dependency vs separate installation), document both patterns

4. **Chart Dependencies**: Should Grafana chart depend on Grafana Operator chart?
   - **Recommendation**: No - chart is independent, assumes Grafana Operator is already installed

---

## Next Steps

1. **Review research findings** - Confirm single-dashboard chart approach (CloudNativePG pattern)
2. **Proceed to `/specify`** - Define detailed requirements for `charts/grafana/` chart structure
3. **Create `/plan`** - Technical implementation plan
4. **Implement chart** - Create `charts/grafana/` with templates (ConfigMap + CRD)
5. **Move MOP chart** - Move current `charts/` to `charts/mop/` and rename
6. **Research dependencies** - Test if MOP chart can depend on Grafana chart
7. **Test installation** - Verify ConfigMap and CRD creation
8. **Update deployment scripts** - Replace manual ConfigMap/CRD with Helm chart
9. **Publish to OCI** - Package and push chart to registry
10. **Future expansion** - Can add `charts/grafana-pgcat/` later following same pattern

---

## References

- **CloudNativePG Grafana Chart**: https://github.com/cloudnative-pg/grafana-dashboards
- **Helm Chart Best Practices**: https://helm.sh/docs/chart_best_practices/
- **Grafana Operator CRDs**: https://grafana.github.io/grafana-operator/docs/api_reference/
- **Helm OCI Support**: https://helm.sh/docs/topics/registries/

---

---

## Changelog

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.2 | 2026-01-04 | [REFINED] Updated to two-chart structure (mop + grafana), added dependency research | System |
| 1.1 | 2026-01-04 | [REFINED] Changed to single-dashboard chart approach, moved location | System |
| 1.0 | 2026-01-04 | Initial research | System |

---

*Research completed with SDD 2.0*
*Ready for specification phase*
