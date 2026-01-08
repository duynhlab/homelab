# Specification: Grafana Dashboard Helm Chart with CRD Support

**Task ID:** mop-grafana-chart
**Created:** 2026-01-04
**Status:** Ready for Planning
**Version:** 1.0

---

## 1. Problem Statement

### The Problem
Currently, Grafana dashboards are managed manually through a combination of:
1. **Kustomization ConfigMapGenerator** - Creates ConfigMaps from JSON files
2. **Manual GrafanaDashboard CRDs** - Created as separate YAML files that must reference the ConfigMaps

This manual approach has several issues:
- **Synchronization Problems**: ConfigMap and CRD must be kept in sync manually
- **No Single Source of Truth**: Dashboard JSON, ConfigMap, and CRD are separate files
- **ConfigMap Size Limits**: Large JSON files (~150KB+) cause annotation size limit errors when using `kubectl apply`
- **Deployment Complexity**: Multiple steps required (kustomization + manual CRD creation)
- **Version Control**: Difficult to track changes across multiple files

### Current Situation
**Location:** `k8s/grafana-operator/dashboards/`

**Current Workflow:**
1. Dashboard JSON file stored: `microservices-dashboard.json` (2843 lines, ~150KB)
2. Kustomization creates ConfigMap: `grafana-dashboard-main` from JSON file
3. Manual YAML file creates GrafanaDashboard CRD: `grafana-dashboard-main.yaml`
4. CRD must manually reference ConfigMap name and key
5. Any change requires updating multiple files

**Pain Points:**
- ConfigMap name changes require updating CRD manually
- JSON file updates require ensuring ConfigMap and CRD stay in sync
- Large files hit Kubernetes annotation size limits
- No Helm-based deployment workflow
- Cannot leverage Helm's dependency management

### Desired Outcome
A Helm chart (`charts/grafana/`) that:
- Creates ConfigMap from `microservices-dashboard.json` automatically
- Creates GrafanaDashboard CRD that references the ConfigMap automatically
- Ensures ConfigMap and CRD are always in sync (single source of truth)
- Avoids ConfigMap annotation size limits (Helm handles this)
- Supports OCI registry publishing for distribution
- Can optionally be used as a dependency by MOP chart
- Follows CloudNativePG chart pattern (proven approach)
- Simple structure that can be extended for additional dashboards later

---

## 2. User Personas

### Primary User: DevOps/SRE Engineer

- **Who:** DevOps or SRE engineer responsible for deploying and managing observability infrastructure
- **Goals:** 
  - Deploy Grafana dashboards reliably and consistently
  - Maintain dashboards as code with proper version control
  - Update dashboards without manual synchronization steps
  - Integrate dashboard deployment into CI/CD pipelines
- **Pain points:** 
  - Manual CRD creation is error-prone
  - ConfigMap and CRD can get out of sync
  - Large JSON files cause deployment failures
  - No standardized deployment process
- **Tech comfort:** High - comfortable with Helm, Kubernetes, YAML

### Secondary User: Platform Engineer

- **Who:** Platform engineer maintaining the Helm chart infrastructure
- **Goals:**
  - Create reusable, maintainable Helm charts
  - Follow established patterns (CloudNativePG)
  - Support OCI registry distribution
  - Enable chart dependencies for coordinated deployment
- **Pain points:**
  - Need to maintain consistency across multiple charts
  - Want to leverage Helm's dependency management
- **Tech comfort:** Very High - expert in Helm, Kubernetes, chart development

---

## 3. Functional Requirements

### FR-1: Create ConfigMap from Dashboard JSON

**Description:** The chart must create a Kubernetes ConfigMap containing the dashboard JSON file content.

**User Story:**
> As a DevOps engineer, I want the Helm chart to automatically create a ConfigMap from the dashboard JSON file so that I don't have to manage ConfigMap creation manually.

**Acceptance Criteria:**
- [ ] Given a dashboard JSON file in `files/microservices-dashboard.json`, when the chart is installed, then a ConfigMap named `grafana-dashboard-main` (configurable) is created
- [ ] Given the ConfigMap is created, when I check its content, then it contains the complete dashboard JSON with proper indentation
- [ ] Given a large JSON file (~150KB), when the chart is installed, then the ConfigMap is created without annotation size limit errors
- [ ] Given the ConfigMap name is configured in values.yaml, when the chart is installed, then the ConfigMap uses the configured name
- [ ] Given labels are configured in values.yaml, when the ConfigMap is created, then it includes the specified labels

**Priority:** Must Have

**Technical Details:**
- Use Helm's `.Files.Get` to load JSON from `files/` directory
- Use `indent` function to properly format JSON in ConfigMap data
- ConfigMap name configurable via `grafanaDashboard.configMapName`
- Labels configurable via `grafanaDashboard.labels`
- Namespace configurable via `namespace` (default: `monitoring`)

---

### FR-2: Create GrafanaDashboard CRD

**Description:** The chart must create a GrafanaDashboard Custom Resource Definition that references the ConfigMap created by FR-1.

**User Story:**
> As a DevOps engineer, I want the Helm chart to automatically create a GrafanaDashboard CRD that references the ConfigMap so that Grafana Operator can discover and load the dashboard.

**Acceptance Criteria:**
- [ ] Given the chart is installed, when the GrafanaDashboard CRD is created, then it references the ConfigMap created by FR-1
- [ ] Given the ConfigMap name is `grafana-dashboard-main`, when the CRD is created, then `spec.configMapRef.name` matches the ConfigMap name
- [ ] Given the JSON file is `microservices-dashboard.json`, when the CRD is created, then `spec.configMapRef.key` matches the file name
- [ ] Given the folder is configured as "Observability", when the CRD is created, then `spec.folder` is set to "Observability"
- [ ] Given datasources are configured, when the CRD is created, then `spec.datasources` contains the configured mappings
- [ ] Given instanceSelector is configured, when the CRD is created, then `spec.instanceSelector.matchLabels` matches the configuration
- [ ] Given the CRD is created, when Grafana Operator processes it, then the dashboard appears in Grafana

**Priority:** Must Have

**Technical Details:**
- CRD name: `microservices-monitoring` (configurable)
- Must reference ConfigMap created by FR-1
- Must include proper instanceSelector to match Grafana instance labels
- Must include datasource mappings for Prometheus
- Must be in the same namespace as ConfigMap

---

### FR-3: Support Configuration via Values

**Description:** The chart must support configuration of all dashboard settings through values.yaml.

**User Story:**
> As a DevOps engineer, I want to configure dashboard settings (namespace, folder, datasources, labels) through values.yaml so that I can customize the deployment without modifying templates.

**Acceptance Criteria:**
- [ ] Given namespace is set in values.yaml, when the chart is installed, then both ConfigMap and CRD are created in that namespace
- [ ] Given folder is set in values.yaml, when the chart is installed, then the CRD uses that folder name
- [ ] Given datasources are configured in values.yaml, when the chart is installed, then the CRD includes those datasource mappings
- [ ] Given labels are configured in values.yaml, when the chart is installed, then the ConfigMap includes those labels
- [ ] Given instanceSelector is configured in values.yaml, when the chart is installed, then the CRD uses that selector
- [ ] Given default values are provided, when the chart is installed without custom values, then it works with sensible defaults

**Priority:** Must Have

**Technical Details:**
- Default namespace: `monitoring`
- Default folder: `Observability`
- Default ConfigMap name: `grafana-dashboard-main`
- Default CRD name: `microservices-monitoring`
- Default instanceSelector: `dashboards: grafana`
- All values should be documented in values.yaml with comments

---

### FR-4: Support OCI Registry Publishing

**Description:** The chart must be packageable and publishable to OCI registry for distribution.

**User Story:**
> As a platform engineer, I want to publish the chart to an OCI registry so that it can be distributed and versioned independently.

**Acceptance Criteria:**
- [ ] Given the chart is complete, when I run `helm package charts/grafana`, then a `.tgz` file is created
- [ ] Given the chart is packaged, when I run `helm push charts/grafana-0.1.0.tgz oci://ghcr.io/duynhne/helm-charts`, then it is published successfully
- [ ] Given the chart is published, when I run `helm install grafana oci://ghcr.io/duynhne/helm-charts/grafana`, then it installs successfully
- [ ] Given Chart.yaml includes proper metadata, when the chart is published, then it includes version, description, and maintainer information

**Priority:** Should Have

**Technical Details:**
- Chart.yaml must include: name, version, description, maintainers, keywords
- Chart type: `application`
- Version format: `0.1.0` (semantic versioning)
- OCI registry: GitHub Container Registry (ghcr.io)

---

### FR-5: Optional Chart Dependency Support

**Description:** The MOP chart should be able to optionally depend on the Grafana chart for coordinated deployment.

**User Story:**
> As a platform engineer, I want the MOP chart to optionally depend on the Grafana chart so that I can deploy both with a single Helm command.

**Acceptance Criteria:**
- [ ] Given the MOP chart Chart.yaml includes grafana dependency, when I run `helm dependency update`, then the dependency is resolved
- [ ] Given the dependency is configured with `condition: grafana.enabled`, when I install MOP chart with `--set grafana.enabled=true`, then both charts are installed
- [ ] Given the dependency is configured, when I install MOP chart with `--set grafana.enabled=false`, then only MOP chart is installed
- [ ] Given the dependency uses `file://../grafana`, when the dependency update runs, then it finds the local chart
- [ ] Given separate installation is preferred, when I install charts separately, then both work independently

**Priority:** Nice to Have

**Technical Details:**
- Dependency pattern: `file://../grafana` for local development
- Condition: `grafana.enabled` to allow optional installation
- Version: `0.1.0` (must match grafana chart version)
- This is optional - separate installation should also work

---

## 4. Non-Functional Requirements

### NFR-1: Chart Structure & Organization

- **Helm Best Practices**: Chart must follow Helm chart best practices
  - Proper directory structure (`templates/`, `files/`, `values.yaml`)
  - Template helpers in `_helpers.tpl`
  - README.md with usage instructions
  - values.schema.json for validation (optional but recommended)

- **Pattern Consistency**: Chart must follow CloudNativePG chart pattern
  - Similar structure to `cnpg-grafana/cluster` chart
  - Use `.Files.Get` for loading JSON files
  - Use `indent` function for JSON formatting
  - Similar values structure

- **File Organization**: 
  - Dashboard JSON in `files/` directory
  - Templates in `templates/` directory
  - Values in `values.yaml` with clear documentation

**Priority:** Must Have

---

### NFR-2: Backward Compatibility

- **ConfigMap Names**: Chart must create ConfigMap with the same name as current setup (`grafana-dashboard-main`)
  - Ensures no breaking changes for existing GrafanaDashboard CRDs
  - Allows gradual migration

- **CRD Names**: Chart must create CRD with the same name as current setup (`microservices-monitoring`)
  - Ensures no breaking changes
  - Allows seamless replacement of manual CRD

- **Namespace**: Default namespace must be `monitoring` (same as current setup)

**Priority:** Must Have

---

### NFR-3: Error Handling & Validation

- **JSON Validation**: Chart should validate that JSON file exists before creating ConfigMap
  - Helm will fail if `.Files.Get` cannot find file
  - Error message should be clear

- **ConfigMap Size**: Chart must handle large JSON files (~150KB+) without annotation size limits
  - Helm's direct ConfigMap creation avoids `kubectl apply` annotation issues
  - No special handling needed, but must be verified

- **Namespace Validation**: Chart should validate namespace exists (or create it)
  - Can use Helm's namespace creation or assume it exists
  - Document requirement in README

**Priority:** Should Have

---

### NFR-4: Documentation

- **README.md**: Must include:
  - Chart description and purpose
  - Installation instructions
  - Configuration options (values.yaml)
  - Examples of common configurations
  - Troubleshooting guide

- **Values Documentation**: All values.yaml fields must have comments explaining:
  - What the field does
  - Default value
  - When to change it
  - Example values

- **Chart.yaml**: Must include:
  - Proper description
  - Keywords for discoverability
  - Maintainer information

**Priority:** Must Have

---

### NFR-5: Extensibility

- **Future Dashboards**: Chart structure must allow easy extension for additional dashboards
  - Can create `charts/grafana-pgcat/` following same pattern
  - No changes needed to existing chart
  - Each dashboard gets its own chart (single-dashboard pattern)

- **Version Management**: Chart versioning must support independent updates
  - Each dashboard chart can be versioned independently
  - No coupling between dashboard charts

**Priority:** Nice to Have

---

## 5. Out of Scope

The following are explicitly NOT included in this feature:

- ❌ **Multi-Dashboard Chart** - This feature creates a single-dashboard chart. Multi-dashboard support (managing multiple dashboards in one chart) is out of scope. Each dashboard gets its own chart.
  - **Why excluded:** Single-dashboard pattern is simpler, follows CloudNativePG approach, and allows independent versioning

- ❌ **Dashboard JSON Creation** - This feature does not create or modify dashboard JSON files. It only packages and deploys existing JSON files.
  - **Why excluded:** Dashboard JSON creation is a separate concern (Grafana dashboard design)

- ❌ **Grafana Operator Installation** - This feature assumes Grafana Operator is already installed. It does not install or manage Grafana Operator.
  - **Why excluded:** Grafana Operator is infrastructure-level component, managed separately

- ❌ **Dashboard Updates via Helm** - This feature does not provide mechanisms to update dashboard content through Helm values. Dashboard JSON must be updated in the `files/` directory and chart repackaged.
  - **Why excluded:** Dashboard JSON is large and complex, better managed as files

- ❌ **Automatic Dashboard Discovery** - This feature does not automatically discover dashboard JSON files. Each dashboard must be explicitly configured.
  - **Why excluded:** Explicit configuration is clearer and more maintainable

- ❌ **Dashboard Versioning Metadata** - This feature does not include per-dashboard version metadata. Chart version applies to the entire chart.
  - **Why excluded:** Chart versioning is sufficient for this use case

- ❌ **Migration Scripts** - This feature does not include scripts to migrate from current kustomization-based approach. Migration is manual.
  - **Why excluded:** Migration is a one-time operation, can be documented instead

---

## 6. Edge Cases & Error Handling

### Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| **Missing JSON File** | Helm installation fails with clear error: "file not found: files/microservices-dashboard.json" |
| **Invalid JSON Content** | ConfigMap is created with invalid JSON. Grafana Operator will fail to load dashboard. Error appears in Grafana Operator logs. |
| **Namespace Doesn't Exist** | Helm installation may fail or create namespace (depends on Helm version and permissions). Document requirement: namespace must exist. |
| **ConfigMap Name Collision** | If ConfigMap already exists, Helm will update it (if using `helm upgrade`) or fail (if using `helm install`). Document in README. |
| **CRD Name Collision** | If GrafanaDashboard CRD already exists, Helm will update it. This is expected behavior for updates. |
| **Grafana Operator Not Installed** | CRD is created but Grafana Operator cannot process it. Dashboard will not appear in Grafana. Document requirement. |
| **Wrong Instance Selector** | CRD is created but Grafana Operator cannot match it to Grafana instance. Dashboard will not appear. Document requirement. |
| **Large JSON File (>1MB)** | ConfigMap is created successfully (Helm handles this). Kubernetes ConfigMap size limit is 1MB, but dashboard JSON should be smaller. |
| **OCI Registry Unavailable** | Chart packaging works, but push fails. User must have registry access. Document registry requirements. |

### Error Scenarios

| Error | User Message | System Action |
|-------|--------------|---------------|
| **JSON file not found** | `Error: file not found: files/microservices-dashboard.json` | Helm installation fails immediately |
| **Invalid Helm template** | `Error: template parsing failed: [details]` | Helm installation fails with template error |
| **Namespace permission denied** | `Error: namespaces "monitoring" is forbidden` | Helm installation fails. User needs namespace permissions. |
| **ConfigMap creation failed** | `Error: ConfigMap creation failed: [details]` | Helm installation fails. Check namespace and permissions. |
| **CRD creation failed** | `Error: GrafanaDashboard creation failed: [details]` | Helm installation fails. Check Grafana Operator is installed. |
| **OCI push authentication failed** | `Error: unauthorized` | Chart push fails. User needs registry authentication. |

---

## 7. Success Metrics

### Key Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Chart Installation Success Rate** | 100% | `helm install` completes without errors |
| **ConfigMap Creation** | 100% | ConfigMap exists after installation: `kubectl get configmap grafana-dashboard-main -n monitoring` |
| **CRD Creation** | 100% | GrafanaDashboard CRD exists: `kubectl get grafanadashboard microservices-monitoring -n monitoring` |
| **Dashboard Visibility** | Dashboard appears in Grafana within 30 seconds | Manual check in Grafana UI or Grafana Operator logs |
| **Chart Package Success** | 100% | `helm package charts/grafana` creates `.tgz` file |
| **OCI Push Success** | 100% | `helm push` completes without errors |
| **Dependency Resolution** | 100% (if implemented) | `helm dependency update` resolves grafana chart |

### Definition of Done

- [ ] All acceptance criteria met for FR-1 through FR-4
- [ ] Chart structure follows Helm best practices
- [ ] Chart follows CloudNativePG pattern
- [ ] ConfigMap created successfully with correct content
- [ ] GrafanaDashboard CRD created successfully and references ConfigMap
- [ ] Dashboard appears in Grafana UI
- [ ] Values.yaml fully documented with comments
- [ ] README.md includes installation and configuration instructions
- [ ] Chart can be packaged: `helm package charts/grafana`
- [ ] Chart can be published to OCI registry (if OCI registry available)
- [ ] Backward compatibility verified (same ConfigMap/CRD names)
- [ ] Edge cases documented and tested
- [ ] No breaking changes to existing setup

---

## 8. Open Questions

- [ ] **Chart Dependency Implementation**: Should MOP chart dependency on Grafana chart be implemented in v1, or deferred to v2?
  - **Recommendation**: Document both approaches, implement dependency support as Nice to Have (FR-5)

- [ ] **Values Schema Validation**: Should we include `values.schema.json` for Helm 3.8+ schema validation?
  - **Recommendation**: Include if time permits, but not blocking for v1

- [ ] **Namespace Creation**: Should chart create namespace if it doesn't exist, or require it to exist?
  - **Recommendation**: Require namespace to exist (document in README). Simpler and more explicit.

- [ ] **Chart Versioning Strategy**: Should chart version follow semantic versioning strictly, or can we use simpler versioning?
  - **Recommendation**: Use semantic versioning (0.1.0, 0.2.0, etc.) for OCI registry compatibility

---

## 9. Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-01-04 | Initial specification | System |

---

## Next Steps

1. **Review spec with stakeholders** - Confirm requirements and priorities
2. **Resolve open questions** - Make decisions on chart dependency and schema validation
3. **Run `/plan mop-grafana-chart`** - Create technical implementation plan
4. **Run `/tasks mop-grafana-chart`** - Break down into actionable tasks
5. **Begin implementation** - Start with FR-1 (ConfigMap creation)

---

## References

- **Research Document**: `specs/active/mop-grafana-chart/research.md`
- **CloudNativePG Chart**: https://github.com/cloudnative-pg/grafana-dashboards
- **Helm Chart Best Practices**: https://helm.sh/docs/chart_best_practices/
- **Grafana Operator CRDs**: https://grafana.github.io/grafana-operator/docs/api_reference/
- **Helm OCI Support**: https://helm.sh/docs/topics/registries/

---

*Specification created with SDD 2.0*
*Based on research: specs/active/mop-grafana-chart/research.md*
