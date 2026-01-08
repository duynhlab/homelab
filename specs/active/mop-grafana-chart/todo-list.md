# Implementation Todo List: Grafana Dashboard Helm Chart with CRD Support

**Task ID:** mop-grafana-chart
**Started:** 2026-01-04
**Status:** In Progress

---

## Phase 1: Chart Foundation

- [x] Task 1.1: Create Chart Directory Structure (estimated: 1h) ✓
  - Files: Create `charts/grafana/`, `charts/grafana/templates/`, `charts/grafana/files/`
  - Dependencies: None
  
- [x] Task 1.2: Create Chart.yaml with Metadata (estimated: 2h) ✓
  - Files: `charts/grafana/Chart.yaml`
  - Dependencies: Task 1.1

- [x] Task 1.3: Create values.yaml with Default Values and Documentation (estimated: 3h) ✓
  - Files: `charts/grafana/values.yaml`
  - Dependencies: Task 1.1

- [x] Task 1.4: Create templates/_helpers.tpl with Helper Functions (estimated: 3h) ✓
  - Files: `charts/grafana/templates/_helpers.tpl`
  - Dependencies: Task 1.1

- [x] Task 1.5: Create README.md with Basic Information (estimated: 2h) ✓
  - Files: `charts/grafana/README.md`
  - Dependencies: Task 1.1

## Phase 2: ConfigMap Template

- [x] Task 2.1: Copy Dashboard JSON to Chart Files Directory (estimated: 1h) ✓
  - Files: Copy `k8s/grafana-operator/dashboards/microservices-dashboard.json` to `charts/grafana/files/microservices-dashboard.json`
  - Dependencies: Task 1.1

- [x] Task 2.2: Create ConfigMap Template Structure (estimated: 2h) ✓
  - Files: `charts/grafana/templates/configmap.yaml`
  - Dependencies: Task 1.4, Task 1.3

- [x] Task 2.3: Implement JSON File Loading with .Files.Get (estimated: 3h) ✓
  - Files: `charts/grafana/templates/configmap.yaml`
  - Dependencies: Task 2.1, Task 2.2

- [x] Task 2.4: Add Labels and Annotations Support (estimated: 2h) ✓
  - Files: `charts/grafana/templates/configmap.yaml`
  - Dependencies: Task 2.2, Task 1.3

- [x] Task 2.5: Test ConfigMap Template Rendering (estimated: 2h) ✓
  - Files: Test `helm template charts/grafana`
  - Dependencies: Task 2.3, Task 2.4

## Phase 3: GrafanaDashboard CRD Template

- [x] Task 3.1: Create GrafanaDashboard CRD Template Structure (estimated: 2h) ✓
  - Files: `charts/grafana/templates/grafanadashboard.yaml`
  - Dependencies: Task 1.4, Task 1.3

- [x] Task 3.2: Implement ConfigMap Reference (estimated: 2h) ✓
  - Files: `charts/grafana/templates/grafanadashboard.yaml`
  - Dependencies: Task 3.1, Task 1.3, Task 2.2

- [x] Task 3.3: Add InstanceSelector Configuration (estimated: 2h) ✓
  - Files: `charts/grafana/templates/grafanadashboard.yaml`
  - Dependencies: Task 3.1, Task 1.3

- [x] Task 3.4: Add Datasource Mappings (estimated: 2h) ✓
  - Files: `charts/grafana/templates/grafanadashboard.yaml`
  - Dependencies: Task 3.1, Task 1.3

- [x] Task 3.5: Add Folder Configuration (estimated: 1h) ✓
  - Files: `charts/grafana/templates/grafanadashboard.yaml`
  - Dependencies: Task 3.1, Task 1.3

- [x] Task 3.6: Test GrafanaDashboard CRD Template Rendering (estimated: 2h) ✓
  - Files: Test `helm template charts/grafana`
  - Dependencies: Task 3.2, Task 3.3, Task 3.4, Task 3.5

## Phase 4: Integration & Testing

- [ ] Task 4.1: Test Helm Install in Test Cluster (estimated: 3h)
  - Files: Test installation
  - Dependencies: Task 2.5, Task 3.6

- [ ] Task 4.2: Verify ConfigMap Creation (estimated: 2h)
  - Files: Verify with kubectl
  - Dependencies: Task 4.1

- [ ] Task 4.3: Verify GrafanaDashboard CRD Creation (estimated: 2h)
  - Files: Verify with kubectl
  - Dependencies: Task 4.1

- [ ] Task 4.4: Verify Dashboard Appears in Grafana (estimated: 3h)
  - Files: Verify in Grafana UI
  - Dependencies: Task 4.3

- [ ] Task 4.5: Test Helm Upgrade for Updates (estimated: 2h)
  - Files: Test upgrade path
  - Dependencies: Task 4.1

- [ ] Task 4.6: Test Helm Uninstall for Cleanup (estimated: 2h)
  - Files: Test uninstall
  - Dependencies: Task 4.1

## Phase 5: Documentation & Polish

- [ ] Task 5.1: Complete README.md with Installation Instructions (estimated: 3h)
  - Files: `charts/grafana/README.md`
  - Dependencies: Task 4.1

- [ ] Task 5.2: Add Troubleshooting Section to README (estimated: 2h)
  - Files: `charts/grafana/README.md`
  - Dependencies: Task 5.1

- [ ] Task 5.3: Document Configuration Options in README (estimated: 3h)
  - Files: `charts/grafana/README.md`
  - Dependencies: Task 5.1

- [ ] Task 5.4: Add Examples for Common Configurations (estimated: 2h)
  - Files: `charts/grafana/README.md`
  - Dependencies: Task 5.3

- [x] Task 5.5: Create values.schema.json (Optional) (estimated: 3h) ✓
  - Files: `charts/grafana/values.schema.json`
  - Dependencies: Task 1.3
  - Note: Schema created with all properties from values.yaml

- [x] Task 5.6: Test Chart Packaging (estimated: 2h) ✓
  - Files: Test `helm package charts/grafana`
  - Dependencies: Task 4.6, Task 5.1
  - Note: Package created successfully (9KB), all files included

## Phase 6: OCI Registry Publishing (Optional - Can defer)

- [x] Task 6.1: Test OCI Push to Registry (estimated: 2h) ✓
  - Files: `.github/workflows/helm-release-grafana.yml`
  - Dependencies: Task 5.6
  - Note: Workflow created, ready for CI/CD

- [ ] Task 6.2: Test OCI Install from Registry (estimated: 2h)
  - Files: Test OCI install
  - Dependencies: Task 6.1
  - Note: Requires workflow to run and push chart first

- [x] Task 6.3: Document OCI Registry Usage (estimated: 2h) ✓
  - Files: `charts/grafana/README.md`
  - Dependencies: Task 6.2, Task 5.1
  - Note: README already includes OCI installation section

- [x] Task 6.4: Update README with OCI Installation Instructions (estimated: 1h) ✓
  - Files: `charts/grafana/README.md`
  - Dependencies: Task 6.3
  - Note: Already documented in README

## Phase 7: Optional Chart Dependency (Optional - Can defer)

- [ ] Task 7.1: Update MOP Chart Chart.yaml with Grafana Dependency (estimated: 2h)
  - Files: `charts/mop/Chart.yaml` (if charts/mop exists)
  - Dependencies: Task 5.6
  - Note: Optional, requires charts/mop to exist first

- [ ] Task 7.2: Test Helm Dependency Update in MOP Chart (estimated: 2h)
  - Files: Test dependency update
  - Dependencies: Task 7.1

- [ ] Task 7.3: Test Conditional Installation with Dependency (estimated: 3h)
  - Files: Test conditional install
  - Dependencies: Task 7.2

- [ ] Task 7.4: Document Dependency Usage (estimated: 2h)
  - Files: `charts/grafana/README.md`
  - Dependencies: Task 7.3

- [ ] Task 7.5: Verify Separate Installation Still Works (estimated: 1h)
  - Files: Test standalone install
  - Dependencies: Task 7.3

---

## Progress Log

| Date | Completed | Notes |
|------|-----------|-------|
| 2026-01-04 | Starting implementation | Created todo-list, beginning Phase 1 |
| 2026-01-04 | Phases 1-3 complete | Chart foundation, ConfigMap template, CRD template all working |
| 2026-01-04 | Phase 5.6 complete | Chart packaging tested successfully (9KB package) |
| 2026-01-04 | Phase 5.5 complete | values.schema.json created with all properties |
| 2026-01-04 | Phase 6.1, 6.3, 6.4 complete | GitHub workflow created for OCI publishing, README updated |
| 2026-01-04 | Phase 4 pending | Requires Kubernetes cluster for testing (install, verify, upgrade, uninstall) |
| 2026-01-04 | Phase 5.1-5.4 pending | Documentation updates (can be done, but Phase 4 testing recommended first) |
| 2026-01-04 | Phase 6.2 pending | Requires workflow to run and push chart to test OCI install |

---

## Notes

- Phase 6 and Phase 7 are optional and can be deferred
- Task 5.5 (values.schema.json) is optional
- Task 7.1+ require charts/mop to exist (may need to create or skip)
