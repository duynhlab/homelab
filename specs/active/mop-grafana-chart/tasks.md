# Implementation Tasks: Grafana Dashboard Helm Chart with CRD Support

**Task ID:** mop-grafana-chart
**Created:** 2026-01-04
**Status:** Ready for Implementation
**Based on:** plan.md

---

## Summary

| Metric | Value |
|--------|-------|
| Total Tasks | 37 |
| Estimated Effort | 80-100 hours (10-12 days) |
| Phases | 7 |
| Critical Path | Phase 1 → Phase 2/3 → Phase 4 → Phase 5 → Phase 6 |

---

## Phase 1: Chart Foundation (Day 1)

**Goal:** Create basic chart structure and metadata
**Estimated:** 8-12 hours

### Task 1.1: Create Chart Directory Structure

**Description:** Create the `charts/grafana/` directory with proper Helm chart structure including subdirectories for templates and files.

**Acceptance Criteria:**
- [ ] Directory `charts/grafana/` exists
- [ ] Subdirectory `charts/grafana/templates/` exists
- [ ] Subdirectory `charts/grafana/files/` exists
- [ ] Directory structure follows Helm best practices

**Effort:** 1 hour
**Priority:** High
**Dependencies:** None
**Assignee:** Unassigned

---

### Task 1.2: Create Chart.yaml with Metadata

**Description:** Create Chart.yaml file with chart metadata including name, version, description, maintainers, and keywords.

**Acceptance Criteria:**
- [ ] Chart.yaml exists at `charts/grafana/Chart.yaml`
- [ ] Chart name is `grafana`
- [ ] Chart version is `0.1.0`
- [ ] Chart type is `application`
- [ ] Description includes purpose and features
- [ ] Maintainer information is included
- [ ] Keywords include: grafana, dashboard, monitoring, observability
- [ ] `helm lint charts/grafana` passes for Chart.yaml

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 1.1
**Assignee:** Unassigned

---

### Task 1.3: Create values.yaml with Default Values and Documentation

**Description:** Create values.yaml file with all configuration options, default values matching current setup, and comprehensive comments documenting each field.

**Acceptance Criteria:**
- [ ] values.yaml exists at `charts/grafana/values.yaml`
- [ ] All fields from plan.md are included:
  - `namespace` (default: `monitoring`)
  - `instanceSelector.matchLabels` (default: `dashboards: grafana`)
  - `grafanaDashboard.configMapName` (default: `grafana-dashboard-main`)
  - `grafanaDashboard.fileName` (default: `microservices-dashboard.json`)
  - `grafanaDashboard.folder` (default: `Observability`)
  - `grafanaDashboard.datasources` (default Prometheus mapping)
  - `grafanaDashboard.labels` (default: `grafana_dashboard: "1"`)
  - `grafanaDashboard.annotations` (default: empty)
  - `crdName` (default: `microservices-monitoring`)
- [ ] Each field has comment explaining:
  - What the field does
  - Default value
  - When to change it
  - Example values
- [ ] Default values match current setup (backward compatible)
- [ ] Values follow CloudNativePG pattern (nested `grafanaDashboard`)

**Effort:** 3 hours
**Priority:** High
**Dependencies:** Task 1.1
**Assignee:** Unassigned

---

### Task 1.4: Create templates/_helpers.tpl with Helper Functions

**Description:** Create _helpers.tpl file with reusable template functions for chart name, fullname, labels, namespace, and other common operations.

**Acceptance Criteria:**
- [ ] _helpers.tpl exists at `charts/grafana/templates/_helpers.tpl`
- [ ] Helper `grafana.name` defined (returns chart name)
- [ ] Helper `grafana.fullname` defined (returns full name with release)
- [ ] Helper `grafana.chart` defined (returns chart name-version)
- [ ] Helper `grafana.labels` defined (returns common labels)
- [ ] Helper `grafana.selectorLabels` defined (returns selector labels)
- [ ] Helper `grafana.namespace` defined (returns namespace from values or release)
- [ ] All helpers follow Helm best practices
- [ ] Helpers support `nameOverride` and `fullnameOverride`
- [ ] `helm template charts/grafana` renders without errors (even if empty)

**Effort:** 3 hours
**Priority:** High
**Dependencies:** Task 1.1
**Assignee:** Unassigned

---

### Task 1.5: Create README.md with Basic Information

**Description:** Create initial README.md file with chart description, purpose, and basic structure. Full documentation will be completed in Phase 5.

**Acceptance Criteria:**
- [ ] README.md exists at `charts/grafana/README.md`
- [ ] Includes chart description and purpose
- [ ] Lists key features (ConfigMap + CRD creation)
- [ ] Mentions CloudNativePG pattern
- [ ] Basic structure documented
- [ ] Placeholder sections for installation, configuration, troubleshooting

**Effort:** 2 hours
**Priority:** Medium
**Dependencies:** Task 1.1
**Assignee:** Unassigned

---

## Phase 2: ConfigMap Template (Day 1-2)

**Goal:** Implement ConfigMap creation from dashboard JSON
**Estimated:** 8-12 hours

### Task 2.1: Copy Dashboard JSON to Chart Files Directory

**Description:** Copy `microservices-dashboard.json` from `k8s/grafana-operator/dashboards/` to `charts/grafana/files/` directory.

**Acceptance Criteria:**
- [ ] File `charts/grafana/files/microservices-dashboard.json` exists
- [ ] File content matches source file exactly
- [ ] File size is ~150KB (2843 lines)
- [ ] JSON is valid (can be parsed)
- [ ] File is readable by Helm's `.Files.Get`

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 1.1
**Assignee:** Unassigned

---

### Task 2.2: Create ConfigMap Template Structure

**Description:** Create `templates/configmap.yaml` with basic ConfigMap structure including metadata and data sections.

**Acceptance Criteria:**
- [ ] File `charts/grafana/templates/configmap.yaml` exists
- [ ] Template includes `apiVersion: v1` and `kind: ConfigMap`
- [ ] Metadata section includes name from values
- [ ] Metadata section includes namespace from helper
- [ ] Data section structure is defined
- [ ] Template uses helper functions for namespace
- [ ] `helm template charts/grafana` renders ConfigMap (may have empty data initially)

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 1.4, Task 1.3
**Assignee:** Unassigned

---

### Task 2.3: Implement JSON File Loading with .Files.Get

**Description:** Implement loading of dashboard JSON file using Helm's `.Files.Get` function and format it properly in ConfigMap data.

**Acceptance Criteria:**
- [ ] Template uses `.Files.Get` to load JSON file
- [ ] File path uses `printf` to construct path: `files/%s` with fileName from values
- [ ] JSON content is properly indented using `indent` function
- [ ] Data key matches fileName from values
- [ ] ConfigMap data contains complete dashboard JSON
- [ ] `helm template charts/grafana` shows ConfigMap with JSON content
- [ ] JSON content is valid and properly formatted

**Effort:** 3 hours
**Priority:** High
**Dependencies:** Task 2.1, Task 2.2
**Assignee:** Unassigned

---

### Task 2.4: Add Labels and Annotations Support

**Description:** Add support for labels and annotations in ConfigMap metadata from values.yaml configuration.

**Acceptance Criteria:**
- [ ] Template includes labels section when `grafanaDashboard.labels` is set
- [ ] Template includes annotations section when `grafanaDashboard.annotations` is set
- [ ] Labels use `toYaml` and `nindent` for proper formatting
- [ ] Annotations use `toYaml` and `nindent` for proper formatting
- [ ] Default labels (`grafana_dashboard: "1"`) are applied
- [ ] `helm template charts/grafana` shows labels and annotations in ConfigMap
- [ ] Custom labels can be added via values.yaml

**Effort:** 2 hours
**Priority:** Medium
**Dependencies:** Task 2.2, Task 1.3
**Assignee:** Unassigned

---

### Task 2.5: Test ConfigMap Template Rendering

**Description:** Test the ConfigMap template rendering with various configurations to ensure it works correctly.

**Acceptance Criteria:**
- [ ] `helm template charts/grafana` renders ConfigMap successfully
- [ ] ConfigMap name matches `grafanaDashboard.configMapName` from values
- [ ] ConfigMap namespace matches `namespace` from values (default: monitoring)
- [ ] ConfigMap data contains complete JSON content
- [ ] ConfigMap data key matches `grafanaDashboard.fileName`
- [ ] Labels are applied correctly
- [ ] `helm lint charts/grafana` passes
- [ ] Template handles missing values gracefully

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 2.3, Task 2.4
**Assignee:** Unassigned

---

## Phase 3: GrafanaDashboard CRD Template (Day 2)

**Goal:** Implement GrafanaDashboard CRD creation
**Estimated:** 8-12 hours

### Task 3.1: Create GrafanaDashboard CRD Template Structure

**Description:** Create `templates/grafanadashboard.yaml` with basic GrafanaDashboard CRD structure including metadata and spec sections.

**Acceptance Criteria:**
- [ ] File `charts/grafana/templates/grafanadashboard.yaml` exists
- [ ] Template includes `apiVersion: grafana.integreatly.org/v1beta1`
- [ ] Template includes `kind: GrafanaDashboard`
- [ ] Metadata section includes name from values (or default)
- [ ] Metadata section includes namespace from helper
- [ ] Metadata section includes labels from helpers
- [ ] Spec section structure is defined
- [ ] `helm template charts/grafana` renders GrafanaDashboard CRD (may be incomplete initially)

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 1.4, Task 1.3
**Assignee:** Unassigned

---

### Task 3.2: Implement ConfigMap Reference

**Description:** Implement ConfigMap reference in GrafanaDashboard CRD spec, ensuring it references the ConfigMap created by configmap.yaml template.

**Acceptance Criteria:**
- [ ] CRD spec includes `configMapRef` section
- [ ] `configMapRef.name` uses `grafanaDashboard.configMapName` from values
- [ ] `configMapRef.key` uses `grafanaDashboard.fileName` from values
- [ ] ConfigMap reference matches ConfigMap created by configmap.yaml
- [ ] `helm template charts/grafana` shows correct ConfigMap reference
- [ ] Reference ensures ConfigMap and CRD are always in sync

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 3.1, Task 1.3, Task 2.2
**Assignee:** Unassigned

---

### Task 3.3: Add InstanceSelector Configuration

**Description:** Add instanceSelector configuration to CRD spec to match Grafana instance labels.

**Acceptance Criteria:**
- [ ] CRD spec includes `instanceSelector` section
- [ ] `instanceSelector.matchLabels` uses values from `instanceSelector.matchLabels` in values.yaml
- [ ] Default value is `dashboards: grafana`
- [ ] Template uses `toYaml` and `nindent` for proper formatting
- [ ] `helm template charts/grafana` shows correct instanceSelector
- [ ] InstanceSelector can be customized via values.yaml

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 3.1, Task 1.3
**Assignee:** Unassigned

---

### Task 3.4: Add Datasource Mappings

**Description:** Add datasource mappings to CRD spec to map template variables in dashboard JSON to Grafana datasources.

**Acceptance Criteria:**
- [ ] CRD spec includes `datasources` section
- [ ] Datasources array uses values from `grafanaDashboard.datasources` in values.yaml
- [ ] Default includes Prometheus mapping: `DS_PROMETHEUS` → `Prometheus`
- [ ] Template uses `toYaml` and `nindent` for proper formatting
- [ ] Template handles empty datasources array gracefully
- [ ] `helm template charts/grafana` shows correct datasource mappings
- [ ] Multiple datasources can be configured via values.yaml

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 3.1, Task 1.3
**Assignee:** Unassigned

---

### Task 3.5: Add Folder Configuration

**Description:** Add folder configuration to CRD spec to organize dashboard in Grafana UI.

**Acceptance Criteria:**
- [ ] CRD spec includes `folder` field
- [ ] Folder value uses `grafanaDashboard.folder` from values.yaml
- [ ] Default value is `Observability`
- [ ] Folder value is properly quoted
- [ ] `helm template charts/grafana` shows correct folder name
- [ ] Folder can be customized via values.yaml

**Effort:** 1 hour
**Priority:** Medium
**Dependencies:** Task 3.1, Task 1.3
**Assignee:** Unassigned

---

### Task 3.6: Test GrafanaDashboard CRD Template Rendering

**Description:** Test the GrafanaDashboard CRD template rendering with various configurations to ensure it works correctly.

**Acceptance Criteria:**
- [ ] `helm template charts/grafana` renders GrafanaDashboard CRD successfully
- [ ] CRD name matches `crdName` from values (or default: `microservices-monitoring`)
- [ ] CRD namespace matches `namespace` from values
- [ ] CRD references ConfigMap correctly (name and key match)
- [ ] InstanceSelector is configured correctly
- [ ] Datasources are configured correctly
- [ ] Folder is configured correctly
- [ ] `helm lint charts/grafana` passes
- [ ] Template handles missing values gracefully

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 3.2, Task 3.3, Task 3.4, Task 3.5
**Assignee:** Unassigned

---

## Phase 4: Integration & Testing (Day 2-3)

**Goal:** Test complete chart installation and verify functionality
**Estimated:** 12-16 hours

### Task 4.1: Test Helm Install in Test Cluster

**Description:** Install the chart in a test Kubernetes cluster and verify the installation process completes successfully.

**Acceptance Criteria:**
- [ ] Test cluster is available (Kind or similar)
- [ ] `helm install grafana charts/grafana --namespace monitoring` completes without errors
- [ ] Helm release is created successfully
- [ ] No template errors during installation
- [ ] Installation logs show successful resource creation
- [ ] Chart can be installed with default values
- [ ] Chart can be installed with custom values

**Effort:** 3 hours
**Priority:** High
**Dependencies:** Task 2.5, Task 3.6
**Assignee:** Unassigned

---

### Task 4.2: Verify ConfigMap Creation

**Description:** Verify that ConfigMap is created correctly after chart installation.

**Acceptance Criteria:**
- [ ] ConfigMap exists: `kubectl get configmap grafana-dashboard-main -n monitoring`
- [ ] ConfigMap name matches `grafanaDashboard.configMapName` from values
- [ ] ConfigMap namespace is `monitoring` (or configured namespace)
- [ ] ConfigMap contains data key matching `grafanaDashboard.fileName`
- [ ] ConfigMap data contains complete dashboard JSON
- [ ] JSON content is valid (can be parsed)
- [ ] ConfigMap labels match values.yaml configuration
- [ ] ConfigMap annotations match values.yaml configuration (if set)

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 4.1
**Assignee:** Unassigned

---

### Task 4.3: Verify GrafanaDashboard CRD Creation

**Description:** Verify that GrafanaDashboard CRD is created correctly and references the ConfigMap.

**Acceptance Criteria:**
- [ ] GrafanaDashboard CRD exists: `kubectl get grafanadashboard microservices-monitoring -n monitoring`
- [ ] CRD name matches `crdName` from values (or default)
- [ ] CRD namespace is `monitoring` (or configured namespace)
- [ ] CRD `spec.configMapRef.name` matches ConfigMap name
- [ ] CRD `spec.configMapRef.key` matches JSON file name
- [ ] CRD `spec.instanceSelector.matchLabels` matches values.yaml
- [ ] CRD `spec.folder` matches values.yaml
- [ ] CRD `spec.datasources` matches values.yaml
- [ ] CRD status shows it's being processed by Grafana Operator

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 4.1
**Assignee:** Unassigned

---

### Task 4.4: Verify Dashboard Appears in Grafana

**Description:** Verify that the dashboard appears in Grafana UI after Grafana Operator processes the CRD.

**Acceptance Criteria:**
- [ ] Grafana Operator is installed and running
- [ ] Grafana Operator processes the GrafanaDashboard CRD
- [ ] Dashboard appears in Grafana UI within 30 seconds
- [ ] Dashboard is in the correct folder (`Observability` or configured folder)
- [ ] Dashboard displays correctly (no errors in Grafana)
- [ ] Dashboard datasources are mapped correctly
- [ ] Dashboard panels load data from Prometheus
- [ ] Grafana Operator logs show successful dashboard sync

**Effort:** 3 hours
**Priority:** High
**Dependencies:** Task 4.3
**Assignee:** Unassigned

---

### Task 4.5: Test Helm Upgrade for Updates

**Description:** Test updating the chart using `helm upgrade` to verify update path works correctly.

**Acceptance Criteria:**
- [ ] Chart is already installed (from Task 4.1)
- [ ] `helm upgrade grafana charts/grafana --namespace monitoring` completes without errors
- [ ] ConfigMap is updated with new content (if JSON changed)
- [ ] GrafanaDashboard CRD is updated with new configuration (if values changed)
- [ ] Dashboard in Grafana reflects updates
- [ ] No downtime during upgrade
- [ ] Upgrade logs show successful resource updates
- [ ] Can upgrade with different values.yaml

**Effort:** 2 hours
**Priority:** Medium
**Dependencies:** Task 4.1
**Assignee:** Unassigned

---

### Task 4.6: Test Helm Uninstall for Cleanup

**Description:** Test uninstalling the chart to verify cleanup works correctly.

**Acceptance Criteria:**
- [ ] Chart is installed (from Task 4.1)
- [ ] `helm uninstall grafana --namespace monitoring` completes without errors
- [ ] ConfigMap is deleted
- [ ] GrafanaDashboard CRD is deleted
- [ ] Dashboard disappears from Grafana UI
- [ ] No orphaned resources remain
- [ ] Can reinstall chart after uninstall
- [ ] Uninstall logs show successful resource deletion

**Effort:** 2 hours
**Priority:** Medium
**Dependencies:** Task 4.1
**Assignee:** Unassigned

---

## Phase 5: Documentation & Polish (Day 3)

**Goal:** Complete documentation and prepare for distribution
**Estimated:** 10-14 hours

### Task 5.1: Complete README.md with Installation Instructions

**Description:** Complete README.md with comprehensive installation instructions, prerequisites, and usage examples.

**Acceptance Criteria:**
- [ ] README.md includes installation section
- [ ] Installation instructions cover:
  - Prerequisites (Grafana Operator, namespace)
  - Basic installation: `helm install grafana charts/grafana`
  - Installation with custom values
  - Installation from OCI registry (placeholder for Phase 6)
- [ ] Examples provided for common scenarios
- [ ] Command examples are tested and work
- [ ] README follows Helm chart documentation best practices

**Effort:** 3 hours
**Priority:** High
**Dependencies:** Task 4.1
**Assignee:** Unassigned

---

### Task 5.2: Add Troubleshooting Section to README

**Description:** Add troubleshooting section to README with common issues and solutions.

**Acceptance Criteria:**
- [ ] README includes troubleshooting section
- [ ] Common issues documented:
  - JSON file not found
  - Grafana Operator not installed
  - Namespace doesn't exist
  - Wrong instanceSelector
  - Dashboard not appearing in Grafana
  - ConfigMap/CRD name collision
- [ ] Each issue includes:
  - Symptoms
  - Root cause
  - Solution steps
- [ ] Troubleshooting guide is clear and actionable

**Effort:** 2 hours
**Priority:** Medium
**Dependencies:** Task 5.1
**Assignee:** Unassigned

---

### Task 5.3: Document Configuration Options in README

**Description:** Document all configuration options in README with examples and use cases.

**Acceptance Criteria:**
- [ ] README includes configuration section
- [ ] All values.yaml fields are documented:
  - `namespace`
  - `instanceSelector`
  - `grafanaDashboard.configMapName`
  - `grafanaDashboard.fileName`
  - `grafanaDashboard.folder`
  - `grafanaDashboard.datasources`
  - `grafanaDashboard.labels`
  - `grafanaDashboard.annotations`
  - `crdName`
- [ ] Each field includes:
  - Description
  - Default value
  - When to change it
  - Example values
- [ ] Examples provided for different configurations
- [ ] Configuration examples are tested

**Effort:** 3 hours
**Priority:** High
**Dependencies:** Task 5.1
**Assignee:** Unassigned

---

### Task 5.4: Add Examples for Common Configurations

**Description:** Add practical examples section to README showing common configuration scenarios.

**Acceptance Criteria:**
- [ ] README includes examples section
- [ ] Examples include:
  - Default installation
  - Custom namespace
  - Custom folder
  - Multiple datasources
  - Custom labels
  - Custom instanceSelector
- [ ] Each example includes:
  - values.yaml snippet
  - Installation command
  - Expected result
- [ ] Examples are tested and work correctly

**Effort:** 2 hours
**Priority:** Medium
**Dependencies:** Task 5.3
**Assignee:** Unassigned

---

### Task 5.5: Create values.schema.json (Optional)

**Description:** Create values.schema.json file for Helm 3.8+ schema validation (optional but recommended).

**Acceptance Criteria:**
- [ ] File `charts/grafana/values.schema.json` exists (optional)
- [ ] Schema validates all values.yaml fields
- [ ] Schema includes type information
- [ ] Schema includes descriptions
- [ ] Schema includes default values
- [ ] `helm lint charts/grafana` validates against schema
- [ ] Schema follows JSON Schema draft-07 format

**Effort:** 3 hours
**Priority:** Low (Nice to Have)
**Dependencies:** Task 1.3
**Assignee:** Unassigned

---

### Task 5.6: Test Chart Packaging

**Description:** Test packaging the chart into a .tgz file for distribution.

**Acceptance Criteria:**
- [ ] `helm package charts/grafana` completes successfully
- [ ] Package file `grafana-0.1.0.tgz` is created
- [ ] Package contains all chart files:
  - Chart.yaml
  - values.yaml
  - templates/ directory
  - files/ directory
- [ ] Package can be extracted and verified
- [ ] `helm lint grafana-0.1.0.tgz` passes
- [ ] Package can be installed: `helm install grafana grafana-0.1.0.tgz`
- [ ] Package size is reasonable (< 200KB)

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 4.6, Task 5.1
**Assignee:** Unassigned

---

## Phase 6: OCI Registry Publishing (Day 3-4)

**Goal:** Publish chart to OCI registry for distribution
**Estimated:** 6-8 hours

### Task 6.1: Test OCI Push to Registry

**Description:** Test pushing the chart package to OCI registry (GitHub Container Registry).

**Acceptance Criteria:**
- [ ] Chart is packaged (from Task 5.6)
- [ ] OCI registry is accessible (ghcr.io)
- [ ] Authentication is configured for OCI registry
- [ ] `helm push grafana-0.1.0.tgz oci://ghcr.io/duynhne/helm-charts` completes successfully
- [ ] Chart is visible in OCI registry
- [ ] Chart version is correct (0.1.0)
- [ ] Chart metadata is preserved in registry

**Effort:** 2 hours
**Priority:** Medium
**Dependencies:** Task 5.6
**Assignee:** Unassigned

---

### Task 6.2: Test OCI Install from Registry

**Description:** Test installing the chart from OCI registry to verify distribution works.

**Acceptance Criteria:**
- [ ] Chart is published to OCI registry (from Task 6.1)
- [ ] `helm install grafana oci://ghcr.io/duynhne/helm-charts/grafana --version 0.1.0` completes successfully
- [ ] Chart installs correctly from OCI registry
- [ ] ConfigMap is created correctly
- [ ] GrafanaDashboard CRD is created correctly
- [ ] Dashboard appears in Grafana
- [ ] OCI installation produces same results as local installation

**Effort:** 2 hours
**Priority:** Medium
**Dependencies:** Task 6.1
**Assignee:** Unassigned

---

### Task 6.3: Document OCI Registry Usage

**Description:** Document OCI registry usage in README including push and install instructions.

**Acceptance Criteria:**
- [ ] README includes OCI registry section
- [ ] Documentation covers:
  - How to push chart to OCI registry
  - How to install from OCI registry
  - Authentication requirements
  - Version management
- [ ] Examples provided for OCI commands
- [ ] OCI registry URL is documented
- [ ] Troubleshooting for OCI issues included

**Effort:** 2 hours
**Priority:** Medium
**Dependencies:** Task 6.2, Task 5.1
**Assignee:** Unassigned

---

### Task 6.4: Update README with OCI Installation Instructions

**Description:** Update README installation section to include OCI registry as primary installation method.

**Acceptance Criteria:**
- [ ] README installation section includes OCI registry option
- [ ] OCI installation is presented as recommended method
- [ ] Local installation is documented as alternative
- [ ] Installation commands are clear and tested
- [ ] Version pinning is documented
- [ ] Examples work correctly

**Effort:** 1 hour
**Priority:** Medium
**Dependencies:** Task 6.3
**Assignee:** Unassigned

---

## Phase 7: Optional - Chart Dependency (Day 4)

**Goal:** Implement optional MOP chart dependency support
**Estimated:** 8-12 hours

### Task 7.1: Update MOP Chart Chart.yaml with Grafana Dependency

**Description:** Add grafana chart as optional dependency in `charts/mop/Chart.yaml`.

**Acceptance Criteria:**
- [ ] `charts/mop/Chart.yaml` includes dependencies section
- [ ] Dependency entry:
  - name: `grafana`
  - version: `0.1.0`
  - repository: `file://../grafana`
  - condition: `grafana.enabled`
- [ ] Dependency is optional (can be disabled)
- [ ] Chart.yaml syntax is valid
- [ ] Dependency follows Helm dependency best practices

**Effort:** 2 hours
**Priority:** Low (Nice to Have)
**Dependencies:** Task 5.6
**Assignee:** Unassigned

---

### Task 7.2: Test Helm Dependency Update in MOP Chart

**Description:** Test `helm dependency update` command in MOP chart to verify dependency resolution works.

**Acceptance Criteria:**
- [ ] MOP chart Chart.yaml includes grafana dependency (from Task 7.1)
- [ ] `cd charts/mop && helm dependency update` completes successfully
- [ ] Dependency is resolved to local chart
- [ ] `charts/mop/charts/grafana-0.1.0.tgz` is created
- [ ] Dependency chart is packaged correctly
- [ ] Dependency update works in CI/CD environment

**Effort:** 2 hours
**Priority:** Low (Nice to Have)
**Dependencies:** Task 7.1
**Assignee:** Unassigned

---

### Task 7.3: Test Conditional Installation with Dependency

**Description:** Test installing MOP chart with grafana dependency enabled/disabled.

**Acceptance Criteria:**
- [ ] MOP chart dependencies are updated (from Task 7.2)
- [ ] `helm install mop charts/mop --set grafana.enabled=true` installs both charts
- [ ] `helm install mop charts/mop --set grafana.enabled=false` installs only MOP chart
- [ ] Conditional installation works correctly
- [ ] Grafana chart resources are created when enabled
- [ ] Grafana chart resources are not created when disabled
- [ ] MOP chart works independently of grafana chart

**Effort:** 3 hours
**Priority:** Low (Nice to Have)
**Dependencies:** Task 7.2
**Assignee:** Unassigned

---

### Task 7.4: Document Dependency Usage

**Description:** Document how to use grafana chart as dependency in MOP chart and as standalone chart.

**Acceptance Criteria:**
- [ ] README includes dependency usage section
- [ ] Documentation covers:
  - How to use as dependency in MOP chart
  - How to use as standalone chart
  - Conditional installation with `grafana.enabled`
  - Dependency update process
- [ ] Examples provided for both approaches
- [ ] Benefits and trade-offs of each approach documented
- [ ] Examples are tested and work

**Effort:** 2 hours
**Priority:** Low (Nice to Have)
**Dependencies:** Task 7.3
**Assignee:** Unassigned

---

### Task 7.5: Verify Separate Installation Still Works

**Description:** Verify that grafana chart can still be installed separately even when dependency support is added.

**Acceptance Criteria:**
- [ ] Grafana chart can be installed standalone: `helm install grafana charts/grafana`
- [ ] Standalone installation works correctly
- [ ] ConfigMap is created
- [ ] GrafanaDashboard CRD is created
- [ ] Dashboard appears in Grafana
- [ ] No dependency on MOP chart required
- [ ] Documentation confirms standalone installation is supported

**Effort:** 1 hour
**Priority:** Low (Nice to Have)
**Dependencies:** Task 7.3
**Assignee:** Unassigned

---

## Dependency Graph

```
Phase 1: Chart Foundation
├── Task 1.1 (Create Directory Structure)
│   ├── Task 1.2 (Chart.yaml)
│   ├── Task 1.3 (values.yaml)
│   ├── Task 1.4 (_helpers.tpl)
│   └── Task 1.5 (README.md)

Phase 2: ConfigMap Template (depends on Phase 1)
├── Task 2.1 (Copy JSON) ──┐
├── Task 2.2 (Template Structure) ──┐
├── Task 2.3 (File Loading) ────────┤
├── Task 2.4 (Labels/Annotations) ─┤
└── Task 2.5 (Test Rendering) ←────┘

Phase 3: GrafanaDashboard CRD Template (depends on Phase 1)
├── Task 3.1 (Template Structure) ──┐
├── Task 3.2 (ConfigMap Reference) ──┤
├── Task 3.3 (InstanceSelector) ─────┤
├── Task 3.4 (Datasources) ──────────┤
├── Task 3.5 (Folder) ───────────────┤
└── Task 3.6 (Test Rendering) ←──────┘

Phase 4: Integration & Testing (depends on Phase 2 & 3)
├── Task 4.1 (Test Install)
│   ├── Task 4.2 (Verify ConfigMap)
│   ├── Task 4.3 (Verify CRD)
│   ├── Task 4.4 (Verify Dashboard)
│   ├── Task 4.5 (Test Upgrade)
│   └── Task 4.6 (Test Uninstall)

Phase 5: Documentation & Polish (depends on Phase 4)
├── Task 5.1 (Complete README)
│   ├── Task 5.2 (Troubleshooting)
│   ├── Task 5.3 (Configuration Docs)
│   └── Task 5.4 (Examples)
├── Task 5.5 (values.schema.json) [Optional]
└── Task 5.6 (Test Packaging)

Phase 6: OCI Registry Publishing (depends on Phase 5)
├── Task 6.1 (Test OCI Push)
│   └── Task 6.2 (Test OCI Install)
│       ├── Task 6.3 (Document OCI)
│       └── Task 6.4 (Update README)

Phase 7: Optional Chart Dependency (depends on Phase 5, independent)
├── Task 7.1 (Update MOP Chart.yaml)
│   └── Task 7.2 (Test Dependency Update)
│       └── Task 7.3 (Test Conditional Install)
│           ├── Task 7.4 (Document Dependency)
│           └── Task 7.5 (Verify Standalone)
```

---

## Quick Reference Checklist

### Phase 1: Chart Foundation
- [ ] Task 1.1: Create Chart Directory Structure
- [ ] Task 1.2: Create Chart.yaml with Metadata
- [ ] Task 1.3: Create values.yaml with Default Values and Documentation
- [ ] Task 1.4: Create templates/_helpers.tpl with Helper Functions
- [ ] Task 1.5: Create README.md with Basic Information

### Phase 2: ConfigMap Template
- [ ] Task 2.1: Copy Dashboard JSON to Chart Files Directory
- [ ] Task 2.2: Create ConfigMap Template Structure
- [ ] Task 2.3: Implement JSON File Loading with .Files.Get
- [ ] Task 2.4: Add Labels and Annotations Support
- [ ] Task 2.5: Test ConfigMap Template Rendering

### Phase 3: GrafanaDashboard CRD Template
- [ ] Task 3.1: Create GrafanaDashboard CRD Template Structure
- [ ] Task 3.2: Implement ConfigMap Reference
- [ ] Task 3.3: Add InstanceSelector Configuration
- [ ] Task 3.4: Add Datasource Mappings
- [ ] Task 3.5: Add Folder Configuration
- [ ] Task 3.6: Test GrafanaDashboard CRD Template Rendering

### Phase 4: Integration & Testing
- [ ] Task 4.1: Test Helm Install in Test Cluster
- [ ] Task 4.2: Verify ConfigMap Creation
- [ ] Task 4.3: Verify GrafanaDashboard CRD Creation
- [ ] Task 4.4: Verify Dashboard Appears in Grafana
- [ ] Task 4.5: Test Helm Upgrade for Updates
- [ ] Task 4.6: Test Helm Uninstall for Cleanup

### Phase 5: Documentation & Polish
- [ ] Task 5.1: Complete README.md with Installation Instructions
- [ ] Task 5.2: Add Troubleshooting Section to README
- [ ] Task 5.3: Document Configuration Options in README
- [ ] Task 5.4: Add Examples for Common Configurations
- [ ] Task 5.5: Create values.schema.json (Optional)
- [ ] Task 5.6: Test Chart Packaging

### Phase 6: OCI Registry Publishing
- [ ] Task 6.1: Test OCI Push to Registry
- [ ] Task 6.2: Test OCI Install from Registry
- [ ] Task 6.3: Document OCI Registry Usage
- [ ] Task 6.4: Update README with OCI Installation Instructions

### Phase 7: Optional - Chart Dependency
- [ ] Task 7.1: Update MOP Chart Chart.yaml with Grafana Dependency
- [ ] Task 7.2: Test Helm Dependency Update in MOP Chart
- [ ] Task 7.3: Test Conditional Installation with Dependency
- [ ] Task 7.4: Document Dependency Usage
- [ ] Task 7.5: Verify Separate Installation Still Works

---

## Risk Areas

| Task | Risk | Mitigation |
|------|------|------------|
| Task 2.3 | JSON file loading fails | Test `.Files.Get` with file path, verify file exists before packaging |
| Task 4.1 | Helm install fails | Use `helm lint` and `helm template --dry-run` before install |
| Task 4.4 | Dashboard doesn't appear | Verify Grafana Operator is running, check CRD status, check Grafana Operator logs |
| Task 6.1 | OCI push fails | Verify authentication, check registry permissions, test with small chart first |
| Task 7.2 | Dependency resolution fails | Verify file path is correct, test with absolute and relative paths |

---

## Next Steps

1. Review task breakdown
2. Assign tasks to developers
3. Run `/implement mop-grafana-chart` to start execution
4. Begin with Phase 1, Task 1.1

---

*Tasks created with SDD 2.0*
*Ready for implementation*
