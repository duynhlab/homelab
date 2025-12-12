# Specification: Go 1.25 Upgrade & Configuration Modernization

**Task ID:** `go125-config-modernization`  
**Status:** Specified  
**Created:** December 12, 2025  
**Owner:** SRE/DevOps Team  
**Priority:** High  
**Estimated Effort:** 17 days (~3 weeks)

**Related Documents:**
- [Research Document](./research.md) - Comprehensive technical analysis
- [AGENTS.md](../../../AGENTS.md) - Project structure guide

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Goals & Objectives](#2-goals--objectives)
3. [Functional Requirements](#3-functional-requirements)
4. [Non-Functional Requirements](#4-non-functional-requirements)
5. [User Stories](#5-user-stories)
6. [Acceptance Criteria](#6-acceptance-criteria)
7. [Success Metrics](#7-success-metrics)
8. [Edge Cases](#8-edge-cases)
9. [Dependencies & Assumptions](#9-dependencies--assumptions)
10. [Out of Scope](#10-out-of-scope)
11. [Implementation Phases](#11-implementation-phases)

---

## 1. Problem Statement

### 1.1 Current Pain Points

**Problem 1: Outdated Go Version (1.23.0)**
- ❌ Missing modern language features (`WaitGroup.Go()`)
- ❌ Older garbage collector (higher overhead)
- ❌ Larger debug binaries (no DWARF5)
- ❌ Manual goroutine management prone to errors

**Problem 2: Scattered Configuration Management**
- ❌ `os.Getenv()` calls scattered across 5+ middleware files
- ❌ No centralized configuration struct
- ❌ No validation layer (typos fail silently at runtime)
- ❌ Hard to test (global environment state)
- ❌ Unclear defaults (magic strings in code)

**Problem 3: Helm Chart Confusion**
- ❌ `env` vs `extraEnv` usage undocumented
- ❌ Team asks questions repeatedly
- ❌ Inconsistent patterns across services
- ❌ No guidance on secret management

**Problem 4: Documentation Sprawl**
- ❌ 24 documentation files (6 redundant)
- ❌ Information duplicated across files
- ❌ Hard to find troubleshooting guides
- ❌ No clear navigation path
- ❌ Some docs outdated (v0.5.0 references)

### 1.2 Affected Users

**Primary Users:**
- **SRE/DevOps Engineers** - Deploy, configure, troubleshoot services
  - Pain: Spend 30+ minutes finding config documentation
  - Pain: Runtime config errors require pod restarts
  - Pain: Unclear where to set service-specific env vars

**Secondary Users:**
- **Future Developers** - Maintain and extend codebase
  - Pain: Unclear configuration patterns
  - Pain: No guidance on adding new config fields
  - Pain: Scattered Go idioms (old WaitGroup patterns)

### 1.3 Business Impact

**Technical Debt:**
- **Current State**: High maintenance burden, scattered patterns
- **Target State**: Centralized config, modern Go idioms, clear docs

**Developer Velocity:**
- **Current**: 30 min to find correct documentation
- **Target**: 5 min with consolidated 15 core docs (5x improvement)

**Reliability:**
- **Current**: Config errors discovered at runtime
- **Target**: 100% validation at startup (fail fast)

**Performance:**
- **Current**: Standard Go 1.23 GC
- **Target**: 10-40% GC overhead reduction with Go 1.25 Green Tea GC

---

## 2. Goals & Objectives

### 2.1 Primary Goals

**G1: Upgrade to Go 1.25** ⭐
- Adopt modern language features
- Reduce GC overhead by 10-40%
- Prepare codebase for 2+ years forward compatibility

**G2: Centralize Configuration Management** ⭐
- Single source of truth for all config
- Validate all settings at startup
- Clear documentation of all env vars

**G3: Clarify Helm Environment Variable Patterns** ⭐
- Document `env` vs `extraEnv` usage
- Provide decision matrix
- Include secret management examples

**G4: Consolidate Documentation** ⭐
- Reduce from 24 to 15 core documents
- Eliminate redundancy
- Improve navigation and searchability

### 2.2 Success Criteria

| Goal | Metric | Target |
|------|--------|--------|
| Go 1.25 Upgrade | Build success rate | 100% |
| Go 1.25 Upgrade | GC overhead reduction | 10-40% |
| Configuration | Startup validation | 100% of typos caught |
| Configuration | Config error location | Startup (not runtime) |
| Helm Documentation | Team questions | Zero (1 month post-rollout) |
| Documentation | File count | 24 → 15 files |
| Documentation | Search time | 30 min → 5 min (83% reduction) |

---

## 3. Functional Requirements

### 3.1 Go 1.25 Upgrade Requirements

**FR-GO-001: Update Go Module**
- **Description**: Update `services/go.mod` to Go 1.25
- **Priority**: High
- **Acceptance Criteria**:
  - `go.mod` contains `go 1.25`
  - `go build ./...` succeeds
  - `go test ./...` passes (100%)

**FR-GO-002: Update Dockerfile**
- **Description**: Update base image to `golang:1.25-alpine`
- **Priority**: High
- **Acceptance Criteria**:
  - `services/Dockerfile` uses `FROM golang:1.25-alpine`
  - All 9 services build successfully
  - Image size unchanged or smaller

**FR-GO-003: Update Dependencies**
- **Description**: Update all dependencies for Go 1.25 compatibility
- **Priority**: High
- **Acceptance Criteria**:
  - `go get -u ./...` completes without errors
  - OpenTelemetry SDK 1.38.0+ verified compatible
  - All transitive dependencies updated

**FR-GO-004: Refactor WaitGroup Usage**
- **Description**: Replace manual `wg.Add(1) + defer wg.Done()` with `wg.Go()`
- **Priority**: Medium
- **Acceptance Criteria**:
  - All 9 service `main.go` files use `wg.Go()`
  - Graceful shutdown logic simplified
  - Shutdown completes within 10 seconds
  - No goroutine leaks (verified via tests)

**FR-GO-005: Add Nil-Check Comments**
- **Description**: Document nil-check patterns in middleware
- **Priority**: Low
- **Acceptance Criteria**:
  - 10+ nil-check locations commented
  - Comments explain "why check", not just "what check"
  - Comments reference Go 1.25 enhanced detection

**FR-GO-006: Create Green Tea GC Staging Build**
- **Description**: Build staging images with `GOEXPERIMENT=greenteagc`
- **Priority**: Medium
- **Acceptance Criteria**:
  - Dockerfile supports `--build-arg GOEXPERIMENT=greenteagc`
  - Staging deployment succeeds
  - GC metrics monitored via Grafana for 48 hours

**FR-GO-007: Update Documentation**
- **Description**: Create Go 1.25 upgrade guide
- **Priority**: Medium
- **Acceptance Criteria**:
  - `docs/development/GO_1.25_UPGRADE.md` created
  - Migration steps documented
  - Breaking changes section included
  - AGENTS.md updated with Go 1.25 notes

### 3.2 Configuration Management Requirements

**FR-CFG-001: Create Config Package**
- **Description**: Create `services/pkg/config/config.go` with structured config
- **Priority**: High
- **Acceptance Criteria**:
  - `Config` struct defined with all fields
  - `TracingConfig`, `ProfilingConfig`, `LoggingConfig` sub-structs exist
  - Fields have struct tags: `env:"ENV_VAR" default:"value"`
  - All current env vars mapped to struct fields

**FR-CFG-002: Implement Config Load Function**
- **Description**: Implement `config.Load()` to parse env vars
- **Priority**: High
- **Acceptance Criteria**:
  - `Load()` reads all env vars
  - Falls back to defaults if env var not set
  - Auto-adjusts sample rate for development env
  - Returns error if required fields missing

**FR-CFG-003: Implement Config Validation**
- **Description**: Implement `config.Validate()` with comprehensive checks
- **Priority**: High
- **Acceptance Criteria**:
  - Validates sample rate (0.0-1.0 range)
  - Validates port (1-65535 range)
  - Validates endpoints (not empty if enabled)
  - Returns clear error messages with field names

**FR-CFG-004: Add Godotenv Support**
- **Description**: Add `github.com/joho/godotenv` for local development
- **Priority**: Medium
- **Acceptance Criteria**:
  - `godotenv/autoload` imported in main packages
  - `.env.example` template created
  - `.env` added to `.gitignore`
  - README includes local dev setup instructions

**FR-CFG-005: Refactor Tracing Middleware**
- **Description**: Update tracing middleware to accept `TracingConfig` struct
- **Priority**: High
- **Acceptance Criteria**:
  - `InitTracingWithConfigStruct(cfg TracingConfig)` function exists
  - Accepts `TempoEndpoint`, `SampleRate`, `Enabled` from struct
  - Maintains backward compatibility with env vars (deprecated)
  - Original `InitTracing()` wraps new function

**FR-CFG-006: Refactor Profiling Middleware**
- **Description**: Update profiling middleware to accept `ProfilingConfig` struct
- **Priority**: High
- **Acceptance Criteria**:
  - `InitProfilingWithConfig(cfg ProfilingConfig)` function exists
  - Accepts `PyroscopeEndpoint`, `Enabled` from struct
  - Maintains backward compatibility with env vars (deprecated)

**FR-CFG-007: Refactor Logging Middleware**
- **Description**: Update logging middleware to accept `LoggingConfig` struct
- **Priority**: High
- **Acceptance Criteria**:
  - `NewLoggerWithConfig(cfg LoggingConfig)` function exists
  - Accepts `Level`, `Format` from struct
  - Maintains backward compatibility with env vars (deprecated)

**FR-CFG-008: Update Service Main Files**
- **Description**: Update all 9 service `main.go` to use config package
- **Priority**: High
- **Acceptance Criteria**:
  - All services call `config.Load()` at startup
  - Config validation errors logged clearly
  - Invalid config causes immediate exit (before server start)
  - Services: auth, user, product, cart, order, review, notification, shipping, shipping-v2

**FR-CFG-009: Create Config Documentation**
- **Description**: Document all configuration options
- **Priority**: Medium
- **Acceptance Criteria**:
  - `docs/development/CONFIGURATION.md` created
  - All env vars documented with defaults
  - Local development setup included
  - Examples for common scenarios

**FR-CFG-010: Maintain Backward Compatibility**
- **Description**: Support old `os.Getenv()` pattern during transition
- **Priority**: Medium
- **Acceptance Criteria**:
  - New config functions coexist with old functions
  - Deprecation warnings logged when old patterns used
  - 2-sprint deprecation period before removal

### 3.3 Helm Chart Documentation Requirements

**FR-HELM-001: Create Helm Chart README**
- **Description**: Create comprehensive `charts/README.md`
- **Priority**: High
- **Acceptance Criteria**:
  - README file created in `charts/` directory
  - Includes env variable configuration section
  - Includes usage examples for all patterns
  - Linked from root README.md

**FR-HELM-002: Document Base Configuration (env)**
- **Description**: Explain when and how to use `env` field
- **Priority**: High
- **Acceptance Criteria**:
  - Section "Base Configuration" exists
  - Explains: "Common env vars applied to all services"
  - Example shows PORT, ENV, LOG_LEVEL
  - Notes: "Set in values.yaml by platform team"

**FR-HELM-003: Document Structured Configuration**
- **Description**: Explain structured config sections (tracing, profiling)
- **Priority**: High
- **Acceptance Criteria**:
  - Section "Structured Configuration" exists
  - Lists available sections: tracing, profiling
  - Examples show typed fields with defaults
  - Explains benefits over flat env vars

**FR-HELM-004: Document Service-Specific Configuration (extraEnv)**
- **Description**: Explain when and how to use `extraEnv` field
- **Priority**: High
- **Acceptance Criteria**:
  - Section "Service-Specific Configuration" exists
  - Explains: "Override defaults or add service-specific vars"
  - Example shows service-specific API keys
  - Notes: "Set in values/<service>.yaml"

**FR-HELM-005: Document Execution Order**
- **Description**: Clarify precedence of env variable sources
- **Priority**: Medium
- **Acceptance Criteria**:
  - Section "Execution Order" exists
  - Lists: 1. env (base) → 2. structured config → 3. extraEnv
  - Explains: extraEnv can override anything
  - Diagram shows merge behavior

**FR-HELM-006: Document Secret Management**
- **Description**: Provide examples for Kubernetes secrets
- **Priority**: High
- **Acceptance Criteria**:
  - Section "Secret Management" exists
  - Example shows `valueFrom.secretKeyRef`
  - Warning: "Never put secrets in plain text values"
  - Links to Kubernetes secrets documentation

**FR-HELM-007: Update AGENTS.md**
- **Description**: Update Helm conventions section in AGENTS.md
- **Priority**: Medium
- **Acceptance Criteria**:
  - AGENTS.md Helm section updated
  - Links to charts/README.md
  - Clarifies env vs extraEnv pattern
  - Examples show per-service overrides

### 3.4 Documentation Consolidation Requirements

**FR-DOC-001: Merge Monitoring Variables Documentation**
- **Description**: Merge `VARIABLES_REGEX.md` into `METRICS.md`
- **Priority**: Medium
- **Acceptance Criteria**:
  - New section "Dashboard Variables" in METRICS.md
  - Regex patterns for namespace filtering included
  - `VARIABLES_REGEX.md` file deleted
  - No broken links (validated)

**FR-DOC-002: Merge Monitoring Label Solutions**
- **Description**: Merge `METRICS_LABEL_SOLUTIONS.md` into `METRICS.md`
- **Priority**: Medium
- **Acceptance Criteria**:
  - New section "Label Configuration" in METRICS.md
  - Kubernetes Downward API patterns included
  - `METRICS_LABEL_SOLUTIONS.md` file deleted
  - No broken links (validated)

**FR-DOC-003: Merge Troubleshooting Guide**
- **Description**: Merge `TROUBLESHOOTING.md` into `getting-started/SETUP.md`
- **Priority**: High
- **Acceptance Criteria**:
  - New section "Troubleshooting" in SETUP.md
  - Organized by component: Prometheus, Grafana, SLO, Metrics
  - `TROUBLESHOOTING.md` file deleted
  - No broken links (validated)

**FR-DOC-004: Merge APM Architecture**
- **Description**: Merge `apm/ARCHITECTURE.md` into `apm/README.md`
- **Priority**: Medium
- **Acceptance Criteria**:
  - New section "Architecture" in apm/README.md
  - System diagrams converted to Mermaid (if needed)
  - `apm/ARCHITECTURE.md` file deleted
  - No broken links (validated)

**FR-DOC-005: Merge APM Profiling Guide**
- **Description**: Merge `apm/PROFILING.md` into `apm/README.md`
- **Priority**: Medium
- **Acceptance Criteria**:
  - New section "Continuous Profiling" in apm/README.md
  - Same level of detail as Tracing section
  - `apm/PROFILING.md` file deleted
  - No broken links (validated)

**FR-DOC-006: Merge SLO Error Budget Policy**
- **Description**: Merge `slo/ERROR_BUDGET_POLICY.md` into `slo/ALERTING.md`
- **Priority**: Medium
- **Acceptance Criteria**:
  - New section "Error Budget Management" in ALERTING.md
  - Policy guidelines and burn rate thresholds included
  - `slo/ERROR_BUDGET_POLICY.md` file deleted
  - No broken links (validated)

**FR-DOC-007: Update Documentation Index**
- **Description**: Update `docs/README.md` after consolidation
- **Priority**: High
- **Acceptance Criteria**:
  - File count updated (24 → 15)
  - References to merged files removed
  - Navigation structure simplified
  - "Recently Updated" section added
  - All links validated

**FR-DOC-008: Create Go 1.25 Upgrade Guide**
- **Description**: Create `docs/development/GO_1.25_UPGRADE.md`
- **Priority**: High
- **Acceptance Criteria**:
  - Migration steps documented
  - New features explained (WaitGroup.Go, Green Tea GC)
  - Breaking changes section
  - Code examples from actual codebase

**FR-DOC-009: Create Configuration Guide**
- **Description**: Create `docs/development/CONFIGURATION.md`
- **Priority**: High
- **Acceptance Criteria**:
  - Config struct documentation
  - All env vars listed with defaults
  - Validation rules explained
  - Local development setup (.env)

**FR-DOC-010: Convert ASCII Diagrams to Mermaid**
- **Description**: Replace all ASCII diagrams with Mermaid (per AGENTS.md)
- **Priority**: Low
- **Acceptance Criteria**:
  - All diagrams use Mermaid syntax
  - No ASCII art diagrams remain
  - Diagrams render correctly in GitHub/Markdown viewers

---

## 4. Non-Functional Requirements

### 4.1 Performance Requirements

**NFR-PERF-001: Build Time**
- **Description**: Go 1.25 build time unchanged or improved
- **Target**: ≤ Current build time (baseline: measured in CI/CD)
- **Measurement**: CI/CD pipeline metrics

**NFR-PERF-002: Garbage Collection Overhead**
- **Description**: GC overhead reduced with Green Tea GC
- **Target**: 10-40% reduction in GC pause time
- **Measurement**: Grafana dashboard GC metrics (existing panels)

**NFR-PERF-003: Startup Time**
- **Description**: Config validation adds minimal startup overhead
- **Target**: < 100ms added to startup time
- **Measurement**: Service logs (time from start to ready)

**NFR-PERF-004: Runtime Performance**
- **Description**: No regression in request handling performance
- **Target**: P95 latency unchanged or improved
- **Measurement**: Prometheus `request_duration_seconds` metric

### 4.2 Compatibility Requirements

**NFR-COMPAT-001: Zero Breaking Changes**
- **Description**: All existing functionality preserved
- **Target**: 100% backward compatibility during transition
- **Measurement**: Integration test pass rate

**NFR-COMPAT-002: OpenTelemetry Compatibility**
- **Description**: OpenTelemetry SDK 1.38.0+ compatible with Go 1.25
- **Target**: All tracing features work unchanged
- **Measurement**: Tempo trace ingestion rate unchanged

**NFR-COMPAT-003: Kubernetes Compatibility**
- **Description**: Helm charts work with existing Kubernetes versions
- **Target**: K8s 1.24+ supported (current: Kind cluster)
- **Measurement**: Successful Helm deployments

**NFR-COMPAT-004: Dependency Compatibility**
- **Description**: All dependencies compatible with Go 1.25
- **Target**: `go get -u ./...` succeeds without conflicts
- **Measurement**: Dependency resolution success

### 4.3 Maintainability Requirements

**NFR-MAINT-001: Config Validation Coverage**
- **Description**: All config errors caught at startup
- **Target**: 100% of typos/invalid values detected before runtime
- **Measurement**: Unit tests for validation logic

**NFR-MAINT-002: Documentation Search Time**
- **Description**: Faster documentation navigation
- **Target**: 50% reduction in search time (30 min → 15 min)
- **Measurement**: Team survey (before/after)

**NFR-MAINT-003: Code Comments**
- **Description**: Critical patterns documented in code
- **Target**: 10+ nil-check locations commented
- **Measurement**: Code review checklist

**NFR-MAINT-004: Clear Error Messages**
- **Description**: Config validation errors are actionable
- **Target**: Error message includes field name, invalid value, expected range
- **Measurement**: Manual testing of error scenarios

### 4.4 Security Requirements

**NFR-SEC-001: Secret Management**
- **Description**: Secrets only via Kubernetes secrets
- **Target**: Zero plaintext secrets in values.yaml
- **Measurement**: Code review + documentation audit

**NFR-SEC-002: Validation Prevents Injection**
- **Description**: Config validation prevents malicious values
- **Target**: Sample rate clamped to 0.0-1.0, ports to 1-65535
- **Measurement**: Security review of validation logic

### 4.5 Testing Requirements

**NFR-TEST-001: Unit Test Coverage**
- **Description**: All unit tests pass with Go 1.25
- **Target**: 100% pass rate
- **Measurement**: `go test ./...` output

**NFR-TEST-002: Integration Test Coverage**
- **Description**: Staging tests validate Go 1.25 deployment
- **Target**: 100% pass rate in staging
- **Measurement**: Integration test suite results

**NFR-TEST-003: Config Validation Tests**
- **Description**: Unit tests for all validation rules
- **Target**: All edge cases covered (invalid rate, port, empty endpoint)
- **Measurement**: Test coverage report (>90%)

---

## 5. User Stories

### US-001: Adopt Go 1.25 for Performance Improvements

**As an** SRE engineer  
**I want to** upgrade all microservices to Go 1.25  
**So that** I can benefit from reduced GC overhead (10-40%) and modern language features

**Priority:** High  
**Effort:** 5 days  
**Assignee:** SRE Team

**Acceptance Criteria:**
- [ ] All 9 services build successfully with Go 1.25
- [ ] `go test ./...` passes 100% in CI/CD
- [ ] Staging deployment succeeds with Green Tea GC enabled
- [ ] GC duration metrics decrease by >10% in staging (48-hour observation)
- [ ] No increase in error rate (monitored via Prometheus)
- [ ] Production rollout completed for all services

**Technical Notes:**
- Use `GOEXPERIMENT=greenteagc` for staging builds
- Monitor Grafana GC panels: "GC duration" and "GC frequency"
- Rollback plan: Revert to previous Docker image tags

---

### US-002: Centralize Configuration with Validation

**As a** DevOps engineer  
**I want** a centralized config struct with startup validation  
**So that** typos in environment variables are caught at startup, not at runtime

**Priority:** High  
**Effort:** 5 days  
**Assignee:** SRE Team

**Acceptance Criteria:**
- [ ] Config package `pkg/config/config.go` created
- [ ] Validation catches invalid sample rate (e.g., "1.5" fails with clear error)
- [ ] Validation catches invalid port (e.g., "99999" fails with clear error)
- [ ] Invalid config logs error message with field name before exit
- [ ] `.env` file works for local development
- [ ] All 9 services integrated with config package
- [ ] Documentation created: `docs/development/CONFIGURATION.md`

**Technical Notes:**
- Maintain backward compatibility for 2 sprints
- Deprecation warnings logged when old `os.Getenv()` used
- Example error: `invalid configuration: invalid sample rate: 1.5 (must be 0-1)`

---

### US-003: Clarify Helm Environment Variable Patterns

**As a** DevOps engineer  
**I want** clear documentation on `env` vs `extraEnv` usage  
**So that** I know where to put service-specific configuration without asking the team

**Priority:** Medium  
**Effort:** 2 days  
**Assignee:** SRE Team

**Acceptance Criteria:**
- [ ] `charts/README.md` created with env variable guide
- [ ] Decision matrix exists (when to use `env`, structured config, `extraEnv`)
- [ ] Examples show all three patterns
- [ ] Secret injection example included (`valueFrom.secretKeyRef`)
- [ ] AGENTS.md Helm section updated with link to charts README
- [ ] Zero team questions about env usage 1 month post-rollout (tracked in Slack)

**Technical Notes:**
- Execution order: `env` → structured config → `extraEnv`
- `extraEnv` can override anything (documented precedence)

---

### US-004: Streamline Documentation Structure

**As an** SRE engineer  
**I want** consolidated documentation (24 → 15 files)  
**So that** I can find troubleshooting guides and setup instructions 50% faster

**Priority:** Medium  
**Effort:** 5 days  
**Assignee:** SRE Team

**Acceptance Criteria:**
- [ ] 6 redundant files merged into related docs
- [ ] No broken internal links (validated with link checker)
- [ ] Troubleshooting section consolidated in `getting-started/SETUP.md`
- [ ] `docs/README.md` index updated (reflects 15 core docs)
- [ ] Team survey shows 50% faster documentation access (30 min → 15 min)
- [ ] All ASCII diagrams converted to Mermaid

**Technical Notes:**
- Merge list: VARIABLES_REGEX, METRICS_LABEL_SOLUTIONS, TROUBLESHOOTING, ARCHITECTURE, PROFILING, ERROR_BUDGET_POLICY
- Test navigation: New team member follows docs to deploy service

---

### US-005: Simplify Graceful Shutdown with WaitGroup.Go()

**As a** developer  
**I want to** use `WaitGroup.Go()` for graceful shutdown  
**So that** the code is clearer and less error-prone (no manual Add/Done pairs)

**Priority:** Low  
**Effort:** 2 days  
**Assignee:** SRE Team

**Acceptance Criteria:**
- [ ] All 9 services use `wg.Go(func() {...})` pattern
- [ ] No more manual `wg.Add(1)` + `defer wg.Done()` pairs
- [ ] Graceful shutdown completes within 10 seconds
- [ ] Zero lost traces/logs/profiles during shutdown (verified in logs)
- [ ] Code comments explain shutdown sequence

**Technical Notes:**
- Shutdown sequence: Stop accepting requests → Flush APM data → Shutdown server
- Example: `wg.Go(func() { tp.Shutdown(ctx) })`

---

## 6. Acceptance Criteria

### 6.1 Go 1.25 Upgrade Criteria

**Build & Test:**
- ✅ `services/go.mod` contains `go 1.25`
- ✅ `services/Dockerfile` uses `FROM golang:1.25-alpine`
- ✅ `go build ./...` succeeds for all services
- ✅ `go test ./...` passes 100% (CI/CD green)
- ✅ Integration tests pass in staging environment

**Performance:**
- ✅ GC overhead reduced by 10-40% with Green Tea GC (Grafana metrics)
- ✅ Build time unchanged or improved (CI/CD pipeline)
- ✅ P95 latency unchanged or improved (Prometheus metrics)
- ✅ No increase in error rate (monitored for 48 hours)

**Code Quality:**
- ✅ All services use `WaitGroup.Go()` pattern
- ✅ 10+ nil-check locations commented
- ✅ No goroutine leaks (verified via tests)

**Documentation:**
- ✅ `docs/development/GO_1.25_UPGRADE.md` created
- ✅ AGENTS.md updated with Go 1.25 notes
- ✅ Migration guide includes rollback instructions

### 6.2 Configuration Management Criteria

**Config Package:**
- ✅ `pkg/config/config.go` exists with `Config` struct
- ✅ `Load()` function parses all env vars with defaults
- ✅ `Validate()` function checks all constraints
- ✅ Unit tests cover all validation rules (>90% coverage)

**Middleware Integration:**
- ✅ `InitTracingWithConfigStruct()` accepts `TracingConfig`
- ✅ `InitProfilingWithConfig()` accepts `ProfilingConfig`
- ✅ `NewLoggerWithConfig()` accepts `LoggingConfig`
- ✅ Backward compatibility maintained (old functions work)

**Service Integration:**
- ✅ All 9 services call `config.Load()` at startup
- ✅ Invalid config causes immediate exit with clear error
- ✅ Error message includes field name and expected value
- ✅ Services: auth, user, product, cart, order, review, notification, shipping, shipping-v2

**Development:**
- ✅ `godotenv/autoload` imported in main packages
- ✅ `.env.example` template created with all vars
- ✅ `.env` added to `.gitignore`
- ✅ Local development setup works with `.env` file

**Documentation:**
- ✅ `docs/development/CONFIGURATION.md` created
- ✅ All env vars documented with defaults
- ✅ Validation rules explained
- ✅ Examples for common scenarios

### 6.3 Helm Documentation Criteria

**Charts README:**
- ✅ `charts/README.md` created
- ✅ Section "Base Configuration (`env`)" exists
- ✅ Section "Structured Configuration" exists
- ✅ Section "Service-Specific Configuration (`extraEnv`)" exists
- ✅ Section "Execution Order" explains precedence
- ✅ Section "Secret Management" shows `valueFrom.secretKeyRef`
- ✅ Examples for all three patterns included

**Integration:**
- ✅ AGENTS.md links to `charts/README.md`
- ✅ Root README.md links to Helm documentation
- ✅ Per-service values use documented patterns

**Team Validation:**
- ✅ Zero questions about env vs extraEnv (1 month post-rollout)
- ✅ New service onboarding uses documented pattern

### 6.4 Documentation Consolidation Criteria

**File Merges:**
- ✅ `monitoring/VARIABLES_REGEX.md` merged into `METRICS.md`
- ✅ `monitoring/METRICS_LABEL_SOLUTIONS.md` merged into `METRICS.md`
- ✅ `monitoring/TROUBLESHOOTING.md` merged into `SETUP.md`
- ✅ `apm/ARCHITECTURE.md` merged into `apm/README.md`
- ✅ `apm/PROFILING.md` merged into `apm/README.md`
- ✅ `slo/ERROR_BUDGET_POLICY.md` merged into `slo/ALERTING.md`
- ✅ 6 files deleted after merge

**Documentation Index:**
- ✅ `docs/README.md` updated (reflects 15 core docs)
- ✅ References to merged files removed
- ✅ Navigation structure simplified
- ✅ "Recently Updated" section added
- ✅ All internal links validated (zero broken links)

**New Documentation:**
- ✅ `docs/development/GO_1.25_UPGRADE.md` created
- ✅ `docs/development/CONFIGURATION.md` created
- ✅ Migration guides include code examples

**Standards:**
- ✅ All diagrams use Mermaid syntax
- ✅ No ASCII art diagrams remain
- ✅ Code examples are complete and runnable
- ✅ Comments explain "why", not just "what"

---

## 7. Success Metrics

### 7.1 Quantifiable KPIs

| Metric | Baseline | Target | Measurement Method |
|--------|----------|--------|-------------------|
| **Build Success Rate** | 100% | 100% | CI/CD pipeline (Go 1.25) |
| **Test Pass Rate** | 100% | 100% | `go test ./...` output |
| **GC Overhead** | Current | -10% to -40% | Grafana GC duration panels |
| **Build Time** | Current | ≤ Baseline | CI/CD pipeline metrics |
| **P95 Latency** | Current | ≤ Baseline | Prometheus `request_duration_seconds` |
| **Error Rate** | Current | ≤ Baseline | Prometheus `error_rate_total` |
| **Config Validation** | 0% (runtime) | 100% (startup) | Unit test coverage |
| **Startup Time** | Current | +< 100ms | Service logs (time to ready) |
| **Documentation Files** | 24 | 15 | File count in `docs/` |
| **Doc Search Time** | 30 min | 15 min | Team survey (before/after) |
| **Helm Questions** | 3-5/month | 0/month | Slack search "env extraEnv" |

### 7.2 Qualitative Success Indicators

**Developer Experience:**
- ✅ Team reports clearer configuration patterns
- ✅ New services onboard faster with documented Helm patterns
- ✅ Fewer runtime config errors (shift to startup validation)

**Code Quality:**
- ✅ More idiomatic Go (WaitGroup.Go usage)
- ✅ Better documented critical patterns (nil checks)
- ✅ Centralized config improves testability

**Operational Excellence:**
- ✅ Faster troubleshooting with consolidated docs
- ✅ Clearer deployment patterns with Helm README
- ✅ Proactive error detection (startup validation)

### 7.3 Definition of Done

**All Criteria Must Be Met:**

1. **Go 1.25 Deployment:**
   - ✅ All 9 services deployed to production with Go 1.25
   - ✅ Green Tea GC enabled if staging shows >15% improvement
   - ✅ Monitored for 1 week with no regressions

2. **Configuration Integration:**
   - ✅ Config package integrated in all services
   - ✅ Validation catches at least 1 real typo during rollout
   - ✅ Development team uses `.env` for local setup

3. **Helm Documentation:**
   - ✅ `charts/README.md` published and linked
   - ✅ Team trained (brown bag session completed)
   - ✅ Zero questions about env patterns for 1 month

4. **Documentation Consolidation:**
   - ✅ 15 core docs live (24 → 15 reduction)
   - ✅ Zero broken links (validated via link checker)
   - ✅ Team survey shows 50% faster information access

5. **Knowledge Transfer:**
   - ✅ Brown bag session presented to team
   - ✅ Migration guides reviewed and approved
   - ✅ Runbooks updated with new patterns

---

## 8. Edge Cases

### 8.1 Configuration Edge Cases

**EC-CFG-001: Invalid Sample Rate String**
- **Scenario**: User sets `OTEL_SAMPLE_RATE="invalid"`
- **Expected Behavior**: Config validation fails at startup
- **Error Message**: `invalid configuration: invalid sample rate: "invalid" (must be 0.0-1.0)`
- **Handling**: Service exits before starting HTTP server

**EC-CFG-002: Sample Rate Out of Range**
- **Scenario**: User sets `OTEL_SAMPLE_RATE="1.5"`
- **Expected Behavior**: Config validation fails at startup
- **Error Message**: `invalid configuration: invalid sample rate: 1.5 (must be 0-1)`
- **Handling**: Service exits before starting HTTP server

**EC-CFG-003: Invalid Port**
- **Scenario**: User sets `PORT="99999"`
- **Expected Behavior**: Config validation fails at startup
- **Error Message**: `invalid configuration: invalid port: 99999 (must be 1-65535)`
- **Handling**: Service exits before starting HTTP server

**EC-CFG-004: Missing Required Endpoint**
- **Scenario**: User sets `TRACING_ENABLED=true` but `TEMPO_ENDPOINT=""`
- **Expected Behavior**: Config validation catches empty endpoint
- **Fallback**: Falls back to default `tempo.monitoring.svc.cluster.local:4318` with warning log
- **Handling**: Service continues with default (non-fatal)

**EC-CFG-005: Conflicting Environment Values**
- **Scenario**: User sets `ENV=production` and `OTEL_SAMPLE_RATE=1.0`
- **Expected Behavior**: Explicit `OTEL_SAMPLE_RATE` takes precedence over env-based auto-adjustment
- **Handling**: Log warning about manual override in production

**EC-CFG-006: .env File Missing in Development**
- **Scenario**: Developer runs service locally without `.env` file
- **Expected Behavior**: godotenv fails silently, falls back to defaults
- **Handling**: Service starts with default config, logs info message

### 8.2 Go 1.25 Upgrade Edge Cases

**EC-GO-001: Dependency Incompatibility**
- **Scenario**: `go get -u ./...` fails due to Go 1.25 incompatibility
- **Expected Behavior**: CI/CD build fails early
- **Handling**: Identify incompatible dependencies, update or pin versions
- **Mitigation**: Test in staging branch before main

**EC-GO-002: Green Tea GC Causes OOM**
- **Scenario**: Green Tea GC triggers out-of-memory errors in staging
- **Expected Behavior**: Pod crashes, restarts with OOMKilled
- **Handling**: Rollback to standard GC, document findings
- **Mitigation**: Monitor memory metrics during 48-hour observation

**EC-GO-003: Enhanced Nil-Pointer Detection Exposes Bug**
- **Scenario**: Go 1.25 panics on previously latent nil-pointer dereference
- **Expected Behavior**: Service crashes with panic stack trace
- **Handling**: Fix nil-check logic, add unit test
- **Benefit**: Catches bug earlier (this is good!)

**EC-GO-004: Build Time Regression**
- **Scenario**: Go 1.25 builds slower than Go 1.23
- **Expected Behavior**: CI/CD pipeline takes longer
- **Handling**: Investigate build cache configuration, optimize if needed
- **Threshold**: < 10% regression acceptable

### 8.3 Helm Deployment Edge Cases

**EC-HELM-001: extraEnv Overrides Critical Base Config**
- **Scenario**: Service owner accidentally overrides `PORT` via `extraEnv`
- **Expected Behavior**: Service starts on wrong port, health checks fail
- **Handling**: Document precedence clearly, include warning in README
- **Prevention**: Code review checklist includes env var validation

**EC-HELM-002: Secret Reference to Non-Existent Secret**
- **Scenario**: `valueFrom.secretKeyRef` references `my-secret` but secret doesn't exist
- **Expected Behavior**: Pod fails to start, K8s event shows "secret not found"
- **Handling**: Helm deployment fails gracefully, error visible in pod describe
- **Prevention**: Pre-deployment secret validation script

**EC-HELM-003: Multiple Services Set Same extraEnv**
- **Scenario**: All services define same `DATABASE_URL` in extraEnv
- **Expected Behavior**: Works correctly (each service has own config)
- **Handling**: No issue, but suggest moving to base `env` if truly shared
- **Optimization**: Document decision matrix for env placement

### 8.4 Documentation Edge Cases

**EC-DOC-001: Broken Link After Merge**
- **Scenario**: Internal link points to merged file
- **Expected Behavior**: 404 error when following link
- **Handling**: Run link checker before PR merge
- **Prevention**: Automated link validation in CI/CD

**EC-DOC-002: Conflicting Information in Merged Sections**
- **Scenario**: Two docs say different things about same topic
- **Expected Behavior**: Confusion during merge
- **Handling**: Manual review to reconcile differences
- **Resolution**: Keep most recent/accurate information

**EC-DOC-003: Orphaned Code Examples**
- **Scenario**: Example references deleted file
- **Expected Behavior**: Example is confusing or broken
- **Handling**: Update examples to reference new file locations
- **Validation**: Test all examples manually

---

## 9. Dependencies & Assumptions

### 9.1 External Dependencies

**DEP-001: Go 1.25 Release**
- **Status**: ✅ Released (December 2024)
- **Version**: 1.25.0 stable
- **Impact**: Upgrade can proceed immediately

**DEP-002: OpenTelemetry SDK Compatibility**
- **Current Version**: go.opentelemetry.io/otel v1.38.0
- **Requirement**: Go 1.21+ minimum (✅ Go 1.25 supported)
- **Impact**: No updates needed for compatibility

**DEP-003: Uber Zap Logger**
- **Current Version**: go.uber.org/zap v1.27.0
- **Requirement**: Go 1.19+ minimum (✅ Go 1.25 supported)
- **Impact**: No updates needed

**DEP-004: Gin Framework**
- **Current Version**: github.com/gin-gonic/gin v1.10.1
- **Requirement**: Go 1.21+ minimum (✅ Go 1.25 supported)
- **Impact**: No updates needed

**DEP-005: godotenv Library**
- **Required Version**: github.com/joho/godotenv v1.5.1
- **Status**: ⚠️ Not yet added to go.mod
- **Impact**: Must add dependency in Phase 2

**DEP-006: Kubernetes Cluster**
- **Current Version**: Kind cluster (K8s 1.24+)
- **Requirement**: Helm 3.x for deployments
- **Impact**: No changes needed

### 9.2 Internal Dependencies

**DEP-007: CI/CD Pipeline**
- **Requirement**: Must support Go 1.25 builder image
- **Status**: ⚠️ Needs update to golang:1.25-alpine
- **Impact**: Update CI/CD Dockerfile before Phase 1

**DEP-008: Monitoring Stack**
- **Requirement**: Prometheus, Grafana, Tempo operational
- **Status**: ✅ Already deployed and working
- **Impact**: No changes needed (metrics remain same)

**DEP-009: Helm Charts**
- **Current Version**: v0.2.0 (microservice chart)
- **Requirement**: No structural changes needed
- **Impact**: Only documentation updates (README)

**DEP-010: Documentation Platform**
- **Requirement**: GitHub Markdown renderer with Mermaid support
- **Status**: ✅ GitHub supports Mermaid diagrams natively
- **Impact**: Diagrams render correctly without plugins

### 9.3 Assumptions

**ASSUME-001: Staging Environment Available**
- **Assumption**: Staging environment exists for Go 1.25 testing
- **Validation**: Confirm staging cluster ready before Phase 1
- **Risk**: If no staging, test in development first

**ASSUME-002: Team Availability**
- **Assumption**: 1 SRE engineer available full-time for 3 weeks
- **Validation**: Confirm resource allocation before starting
- **Risk**: Timeline extends if part-time allocation

**ASSUME-003: No Breaking Changes in Go 1.25**
- **Assumption**: Research confirmed no breaking changes for our codebase
- **Validation**: Verified via Go 1.25 release notes
- **Risk**: Minimal (research was thorough)

**ASSUME-004: Config Patterns Stable**
- **Assumption**: No new APM tools added during migration
- **Validation**: Freeze APM changes during Phase 2
- **Risk**: New tools require config struct updates

**ASSUME-005: Documentation Merge Agreement**
- **Assumption**: Team agrees with 24→15 consolidation plan
- **Validation**: Review research doc and get approval
- **Risk**: May need to keep some files if team objects

**ASSUME-006: Rollback Plan Exists**
- **Assumption**: Previous Docker images available for rollback
- **Validation**: Verify image retention policy in registry
- **Risk**: Cannot rollback if images purged

---

## 10. Out of Scope

### 10.1 Explicitly Excluded

**OOS-001: Database Migration**
- **Reason**: Not related to Go upgrade or config management
- **Future**: Consider separate project if needed

**OOS-002: API Versioning Changes**
- **Reason**: Existing v1/v2 API structure works fine
- **Future**: Only if breaking changes needed

**OOS-003: Microservices Architecture Changes**
- **Reason**: Focus is modernization, not restructuring
- **Future**: Consider in separate architecture review

**OOS-004: Performance Optimization Beyond GC**
- **Reason**: Green Tea GC is automatic, no manual tuning
- **Future**: Profile-guided optimization in separate project

**OOS-005: New Monitoring Metrics**
- **Reason**: Existing 6 custom metrics are sufficient
- **Future**: Add metrics based on operational needs

**OOS-006: Kubernetes Version Upgrade**
- **Reason**: Kind cluster K8s version is stable
- **Future**: Upgrade if new K8s features needed

**OOS-007: Helm Chart Restructuring**
- **Reason**: Current structure (values/, templates/) is good
- **Future**: Only if major architectural changes

**OOS-008: Automated Config Generation**
- **Reason**: Manual config struct is sufficient
- **Future**: Consider code generation if >50 config fields

**OOS-009: Multi-Environment Config Files**
- **Reason**: Helm values per service is sufficient
- **Future**: Consider if >3 environments needed

**OOS-010: Documentation Translation**
- **Reason**: English documentation is sufficient for team
- **Future**: Vietnamese translation if team requests

### 10.2 Deferred to Future Phases

**DEFERRED-001: Uber fx Dependency Injection**
- **Reason**: Config struct pattern is simpler
- **Future**: Consider if service complexity grows significantly
- **Timeline**: Review in 6 months

**DEFERRED-002: Viper Configuration Library**
- **Reason**: Our config package is sufficient
- **Future**: Consider if remote config sources needed (Consul, etcd)
- **Timeline**: Review if distributed config required

**DEFERRED-003: Grafana Dashboard Updates**
- **Reason**: Existing 32 panels cover all metrics
- **Future**: Add Go 1.25 GC-specific panels if needed
- **Timeline**: After Phase 1 completion

**DEFERRED-004: Automated Documentation Generation**
- **Reason**: 15 docs are maintainable manually
- **Future**: Consider tools like docusaurus if >50 docs
- **Timeline**: Review in 1 year

**DEFERRED-005: Config Schema Validation**
- **Reason**: Code-based validation is sufficient
- **Future**: Consider JSON schema if external tools need it
- **Timeline**: Review if third-party integrations needed

---

## 11. Implementation Phases

### Phase 1: Go 1.25 Upgrade (Week 1 - 5 Days)

**Objective:** Upgrade all services to Go 1.25 with Green Tea GC testing

**Day 1-2: Preparation & Build**
- [ ] Update `services/go.mod` to `go 1.25`
- [ ] Update `services/Dockerfile` to `FROM golang:1.25-alpine`
- [ ] Update CI/CD pipeline to use golang:1.25 builder
- [ ] Run `go get -u ./...` to update dependencies
- [ ] Run `go mod tidy` to clean up
- [ ] Build all 9 services locally: `go build ./...`
- [ ] Run all tests locally: `go test ./...`
- [ ] Verify test pass rate: 100%

**Day 3: Code Refactoring**
- [ ] Refactor graceful shutdown in all 9 `cmd/*/main.go`:
  - Replace `wg.Add(1) + defer wg.Done()` with `wg.Go()`
  - Add comments explaining shutdown sequence
- [ ] Add nil-check comments in middleware:
  - `services/pkg/middleware/tracing.go` (5 locations)
  - `services/pkg/middleware/logging.go` (3 locations)
  - `services/pkg/middleware/profiling.go` (2 locations)
- [ ] Run tests after refactoring: `go test ./...`

**Day 4: Staging Deployment**
- [ ] Create staging Docker images with Go 1.25
- [ ] Create experimental build with `GOEXPERIMENT=greenteagc`
- [ ] Deploy to staging environment
- [ ] Verify all services start successfully
- [ ] Run integration tests in staging
- [ ] Start 48-hour monitoring period

**Day 5: Monitoring & Documentation**
- [ ] Monitor Grafana GC metrics:
  - GC duration (target: 10-40% reduction)
  - GC frequency
  - Memory usage
- [ ] Monitor Prometheus metrics:
  - Request duration (P95 latency unchanged)
  - Error rate (unchanged or improved)
- [ ] Create `docs/development/GO_1.25_UPGRADE.md`
- [ ] Update `AGENTS.md` with Go 1.25 notes
- [ ] Document findings and decision on Green Tea GC

**Phase 1 Deliverables:**
- ✅ All services build with Go 1.25
- ✅ All tests pass (100%)
- ✅ Staging deployment validated
- ✅ GC metrics improved (10-40%)
- ✅ Upgrade guide documented

**Phase 1 Risks:**
- ⚠️ Dependency incompatibility (mitigation: test early)
- ⚠️ Green Tea GC OOM (mitigation: monitor closely, rollback if needed)

---

### Phase 2: Configuration Modernization (Week 2 - 5 Days)

**Objective:** Centralize config management with validation

**Day 1: Create Config Package**
- [ ] Create `services/pkg/config/config.go`
- [ ] Define `Config` struct with all fields:
  - Server: Port, Env
  - Tracing: Enabled, TempoEndpoint, SampleRate
  - Profiling: Enabled, PyroscopeEndpoint
  - Logging: Level, Format
- [ ] Implement `Load()` function:
  - Parse env vars with `getEnvOrDefault()`
  - Auto-adjust sample rate for development
- [ ] Implement `Validate()` function:
  - Sample rate (0.0-1.0)
  - Port (1-65535)
  - Endpoints (not empty if enabled)
- [ ] Write unit tests for config package:
  - Valid config succeeds
  - Invalid sample rate fails
  - Invalid port fails
  - Missing endpoint falls back to default

**Day 2: Refactor Middleware**
- [ ] Update `pkg/middleware/tracing.go`:
  - Add `InitTracingWithConfigStruct(cfg config.TracingConfig)`
  - Keep `InitTracing()` for backward compatibility (deprecated)
- [ ] Update `pkg/middleware/profiling.go`:
  - Add `InitProfilingWithConfig(cfg config.ProfilingConfig)`
  - Keep `InitProfiling()` for backward compatibility (deprecated)
- [ ] Update `pkg/middleware/logging.go`:
  - Add `NewLoggerWithConfig(cfg config.LoggingConfig)`
  - Keep `NewLogger()` for backward compatibility (deprecated)
- [ ] Add deprecation warnings (log when old functions used)
- [ ] Test middleware with both old and new patterns

**Day 3: Add godotenv Support**
- [ ] Add `github.com/joho/godotenv` to `go.mod`
- [ ] Import `_ "github.com/joho/godotenv/autoload"` in all main packages
- [ ] Create `.env.example` template:
  ```bash
  # Server Configuration
  ENV=development
  PORT=8080
  
  # Tracing Configuration
  TRACING_ENABLED=true
  TEMPO_ENDPOINT=localhost:4318
  OTEL_SAMPLE_RATE=1.0
  
  # Profiling Configuration
  PROFILING_ENABLED=true
  PYROSCOPE_ENDPOINT=http://localhost:4040
  
  # Logging Configuration
  LOG_LEVEL=debug
  LOG_FORMAT=console
  ```
- [ ] Add `.env` to `.gitignore`
- [ ] Test local development with `.env` file

**Day 4-5: Update Services**
- [ ] Update all 9 service `cmd/*/main.go`:
  - Add `cfg, err := config.Load()` at startup
  - Add error handling: log and exit if validation fails
  - Pass config to middleware initialization
  - Services: auth, user, product, cart, order, review, notification, shipping, shipping-v2
- [ ] Test each service individually:
  - Valid config starts successfully
  - Invalid config fails at startup with clear error
  - `.env` file works for local development
- [ ] Run integration tests with new config pattern
- [ ] Create `docs/development/CONFIGURATION.md`:
  - Config struct documentation
  - All env vars with defaults
  - Validation rules
  - Local development setup

**Phase 2 Deliverables:**
- ✅ Config package with validation
- ✅ All middleware accept config structs
- ✅ All 9 services integrated
- ✅ godotenv support for local dev
- ✅ Configuration guide documented

**Phase 2 Risks:**
- ⚠️ Breaking changes during transition (mitigation: maintain backward compatibility)
- ⚠️ Team unfamiliar with new pattern (mitigation: documentation + brown bag session)

---

### Phase 3: Helm Documentation (Week 2 - 2 Days)

**Objective:** Clarify `env` vs `extraEnv` patterns

**Day 1: Create Helm README**
- [ ] Create `charts/README.md`:
  - Project overview
  - Installation instructions
- [ ] Add section "Environment Variable Configuration":
  - Subsection "Base Configuration (`env`)"
  - Subsection "Structured Configuration"
  - Subsection "Service-Specific Configuration (`extraEnv`)"
  - Subsection "Execution Order"
  - Subsection "Secret Management"
- [ ] Include decision matrix:
  | When to Use | Field | Example |
  |-------------|-------|---------|
  | Common to all services | `env` | PORT, ENV, LOG_LEVEL |
  | Feature-specific with defaults | Structured (e.g., `tracing`) | TEMPO_ENDPOINT, OTEL_SAMPLE_RATE |
  | Service-specific overrides | `extraEnv` | API_KEY, DATABASE_URL |
- [ ] Add examples for each pattern:
  - Base `env` example (values.yaml)
  - Structured config example (tracing, profiling)
  - Service-specific `extraEnv` example (values/user.yaml)
  - Secret injection example (`valueFrom.secretKeyRef`)

**Day 2: Update Project Documentation**
- [ ] Update `AGENTS.md` Helm section:
  - Link to `charts/README.md`
  - Summarize env vs extraEnv pattern
  - Include per-service override examples
- [ ] Update root `README.md`:
  - Add link to Helm chart documentation
  - Include quick deployment examples
- [ ] Review with team (async Slack review)
- [ ] Incorporate feedback

**Phase 3 Deliverables:**
- ✅ `charts/README.md` with env variable guide
- ✅ Decision matrix for env placement
- ✅ Secret management examples
- ✅ AGENTS.md and README.md updated

**Phase 3 Risks:**
- ⚠️ Team disagrees with pattern (mitigation: present research findings)
- ⚠️ Missing edge cases (mitigation: collect questions during review)

---

### Phase 4: Documentation Consolidation (Week 3 - 5 Days)

**Objective:** Reduce from 24 to 15 core documents

**Day 1: Merge Monitoring Documentation**
- [ ] Merge `monitoring/VARIABLES_REGEX.md` → `monitoring/METRICS.md`:
  - Add section "Dashboard Variables"
  - Include regex patterns for namespace filtering
  - Delete source file
- [ ] Merge `monitoring/METRICS_LABEL_SOLUTIONS.md` → `monitoring/METRICS.md`:
  - Add section "Label Configuration"
  - Include Kubernetes Downward API patterns
  - Delete source file
- [ ] Merge `monitoring/TROUBLESHOOTING.md` → `getting-started/SETUP.md`:
  - Add section "Troubleshooting" at end
  - Organize by component: Prometheus, Grafana, SLO, Metrics
  - Delete source file
- [ ] Validate internal links (find all references to merged files)

**Day 2: Merge APM Documentation**
- [ ] Merge `apm/ARCHITECTURE.md` → `apm/README.md`:
  - Add section "Architecture" after overview
  - Convert ASCII diagrams to Mermaid (if any)
  - Delete source file
- [ ] Merge `apm/PROFILING.md` → `apm/README.md`:
  - Add section "Continuous Profiling (Pyroscope)"
  - Match level of detail with Tracing section
  - Delete source file
- [ ] Validate internal links

**Day 3: Merge SLO Documentation & Update Index**
- [ ] Merge `slo/ERROR_BUDGET_POLICY.md` → `slo/ALERTING.md`:
  - Add section "Error Budget Management"
  - Include policy guidelines and burn rate thresholds
  - Delete source file
- [ ] Update `docs/README.md` index:
  - Update file count (24 → 15)
  - Remove references to merged files
  - Update navigation structure
  - Add "Recently Updated" section at top
  - Update last modified date

**Day 4: Create New Development Guides**
- [ ] Create `docs/development/GO_1.25_UPGRADE.md` (if not done in Phase 1):
  - Migration steps
  - New features explained
  - Breaking changes section
  - Code examples from actual codebase
- [ ] Create `docs/development/CONFIGURATION.md` (if not done in Phase 2):
  - Config struct documentation
  - All env vars with defaults
  - Validation rules
  - Local development setup
- [ ] Update `docs/development/ERROR_HANDLING.md`:
  - Include nil-check patterns
  - Reference Go 1.25 enhanced detection

**Day 5: Final Validation & Standards Compliance**
- [ ] Convert all ASCII diagrams to Mermaid:
  - Search for ASCII art patterns (`┌─┐`, `│`, `→`)
  - Replace with Mermaid equivalents
  - Verify rendering in GitHub
- [ ] Run link checker:
  - Check all internal links
  - Check all external links
  - Fix broken links
- [ ] Manual documentation review:
  - Test all code examples
  - Verify all commands work
  - Check formatting consistency
- [ ] Create PR with all documentation changes
- [ ] Team review and approval

**Phase 4 Deliverables:**
- ✅ 6 files merged, 6 files deleted
- ✅ `docs/README.md` updated (reflects 15 core docs)
- ✅ 3 new development guides created
- ✅ All ASCII diagrams converted to Mermaid
- ✅ Zero broken links (validated)

**Phase 4 Risks:**
- ⚠️ Breaking links during merge (mitigation: automated link checker)
- ⚠️ Conflicting information (mitigation: manual review to reconcile)
- ⚠️ Team objects to consolidation (mitigation: reference research findings)

---

## 12. Review & Approval

### 12.1 Specification Review Checklist

**Completeness:**
- ✅ All 4 work streams defined (Go upgrade, config, Helm docs, doc consolidation)
- ✅ 40+ functional requirements with clear acceptance criteria
- ✅ 9 non-functional requirements across performance, compatibility, maintainability
- ✅ 5 user stories with SRE/DevOps perspective
- ✅ Success metrics are quantifiable and measurable
- ✅ Edge cases identified and handled
- ✅ Dependencies and assumptions documented
- ✅ Out of scope items explicitly listed
- ✅ Implementation phases with day-by-day breakdown

**Quality:**
- ✅ All requirements are testable
- ✅ Acceptance criteria are specific and measurable
- ✅ User stories follow INVEST principles
- ✅ Success metrics have clear baselines and targets
- ✅ Edge cases have documented handling strategies

**Feasibility:**
- ✅ Timeline is realistic (3 weeks with 1 FTE)
- ✅ Dependencies are available or obtainable
- ✅ Assumptions are reasonable and validated
- ✅ Risks are identified with mitigation plans

### 12.2 Approval Sign-Off

**Reviewed By:**
- [ ] SRE Lead - Technical feasibility
- [ ] DevOps Engineer - Deployment strategy
- [ ] Development Team - Config patterns
- [ ] Documentation Owner - Doc consolidation plan

**Approved By:**
- [ ] Engineering Manager - Resource allocation
- [ ] Technical Lead - Architecture decisions

**Approval Date:** _____________

---

## 13. Next Steps

**After Approval:**

1. **Create Implementation Tasks** - Use `/plan` command to break down into detailed tasks
2. **Generate Task List** - Use `/tasks` command to create todo-list.md
3. **Schedule Work** - Allocate 3-week timeline in project board
4. **Kickoff Meeting** - Present specification to team
5. **Begin Phase 1** - Start Go 1.25 upgrade in Week 1

**Timeline:**
- **Specification Review:** 2-3 days
- **Phase 1 (Go 1.25):** Week 1 (5 days)
- **Phase 2 (Config):** Week 2 (5 days)
- **Phase 3 (Helm Docs):** Week 2 (2 days, parallel with Phase 2 Day 4-5)
- **Phase 4 (Doc Consolidation):** Week 3 (5 days)
- **Total:** 17 days (~3 weeks)

---

**Document Version:** 1.0  
**Last Updated:** December 12, 2025  
**Status:** Awaiting Approval

