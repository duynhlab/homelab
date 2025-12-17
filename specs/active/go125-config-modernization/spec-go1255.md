# Specification: Go 1.25.5 Security Upgrade

**Task ID:** `go125-config-modernization`  
**Created:** December 17, 2025  
**Status:** Ready for Planning  
**Version:** 1.0  
**Priority:** HIGH (Security Patch)

**Related Documents:**
- [Research Document](./research-go1255.md) - Comprehensive Go 1.25.5 analysis
- [Original Spec](./spec.md) - Go 1.25 upgrade specification

---

## 1. Problem Statement

### The Problem

The project currently uses Go 1.25 (and CI uses Go 1.23), but Go 1.25.5 was released on December 2, 2025 with **2 critical security patches** for the `crypto/x509` package:

1. **CVE-2025-61729**: Resource exhaustion vulnerability in `HostnameError.Error()`
2. **CVE-2025-61727**: Domain exclusion constraint bypass for wildcard SAN entries

All 9 microservices use TLS/certificates and are vulnerable to these security issues.

### Current Situation

**Version Inconsistencies:**
- `services/go.mod`: `go 1.25` ✅ (OK - patch versions don't require go.mod change)
- `services/Dockerfile`: `golang:1.25-alpine` ⚠️ (should pin to 1.25.5)
- `.github/workflows/build-images.yml`: `go-version: '1.23'` ❌ (CRITICAL - outdated)
- Local development: `go1.22.12` ⚠️ (outdated)
- Documentation: Mixed references (1.23, 1.25, 1.25.5)

**Security Risk:**
- Services using TLS/certificates are vulnerable to CVE-2025-61729 and CVE-2025-61727
- CI/CD pipeline uses outdated Go 1.23, creating security inconsistency
- Production builds may not include security fixes

### Desired Outcome

**All project components use Go 1.25.5:**
- ✅ CI/CD pipeline builds with Go 1.25.5
- ✅ Docker images built with Go 1.25.5
- ✅ Local development uses Go 1.25.5
- ✅ Documentation references Go 1.25.5 consistently
- ✅ All services protected from security vulnerabilities
- ✅ Build verification script confirms Go 1.25.5 usage

---

## 2. User Personas

### Primary User: SRE/DevOps Engineer

- **Who:** Team member responsible for infrastructure and deployments
- **Goals:** 
  - Ensure all services are secure and up-to-date
  - Maintain consistent Go versions across environments
  - Deploy security patches quickly
- **Pain points:** 
  - Version inconsistencies between CI and production
  - Security vulnerabilities in production code
  - Unclear documentation about Go version requirements
- **Tech comfort:** High

### Secondary User: Developer

- **Who:** Team member writing and maintaining microservice code
- **Goals:**
  - Use latest Go features and security fixes
  - Have consistent development environment
  - Clear documentation on Go version requirements
- **Pain points:**
  - Local Go version doesn't match CI/production
  - Unclear which Go version to use
- **Tech comfort:** High

---

## 3. Functional Requirements

### FR-1: Update CI/CD Pipeline to Go 1.25.5

**Description:** GitHub Actions workflow must use Go 1.25.5 for all builds

**User Story:**
> As an SRE engineer, I want CI/CD to use Go 1.25.5 so that all builds include security patches and match production.

**Acceptance Criteria:**
- [ ] `.github/workflows/build-images.yml` uses `go-version: '1.25.5'`
- [ ] All matrix builds (9 services) use Go 1.25.5
- [ ] Build verification checks run with Go 1.25.5
- [ ] CI builds succeed with Go 1.25.5
- [ ] Docker images are built with Go 1.25.5 toolchain

**Priority:** Must Have (CRITICAL - Security)

**Files to Modify:**
- `.github/workflows/build-images.yml` (Line 60)

---

### FR-2: Update Dockerfile to Go 1.25.5

**Description:** Production Docker images must be built with Go 1.25.5

**User Story:**
> As an SRE engineer, I want Docker images built with Go 1.25.5 so that production services include security patches.

**Acceptance Criteria:**
- [ ] `services/Dockerfile` uses `FROM golang:1.25.5-alpine`
- [ ] All 9 services build successfully with Go 1.25.5
- [ ] Docker images are reproducible (pinned version)
- [ ] Build verification script confirms Go 1.25.5 usage

**Priority:** Must Have (CRITICAL - Security)

**Files to Modify:**
- `services/Dockerfile` (Line 2)

---

### FR-3: Update Documentation to Go 1.25.5

**Description:** All documentation must reference Go 1.25.5 consistently

**User Story:**
> As a developer, I want documentation to clearly state Go 1.25.5 requirement so that I use the correct version locally.

**Acceptance Criteria:**
- [ ] `AGENTS.md` references Go 1.25.5 in prerequisites
- [ ] `README.md` states Go 1.25.5 requirement
- [ ] `specs/system-context/06-technology-stack.md` shows Go 1.25.5
- [ ] `specs/system-context/08-development-workflow.md` lists Go 1.25.5
- [ ] All version tables updated consistently
- [ ] No references to Go 1.23 or Go 1.25 (without patch version)

**Priority:** Should Have (Important - Consistency)

**Files to Modify:**
- `AGENTS.md`
- `README.md`
- `specs/system-context/06-technology-stack.md`
- `specs/system-context/08-development-workflow.md`
- `specs/active/go125-config-modernization/research.md` (note 1.25.5 availability)

---

### FR-4: Verify Build Compatibility

**Description:** All services must build and run correctly with Go 1.25.5

**User Story:**
> As a developer, I want all services to build successfully with Go 1.25.5 so that I can develop and deploy without issues.

**Acceptance Criteria:**
- [ ] `./scripts/00-verify-build.sh` passes with Go 1.25.5
- [ ] All 9 services build successfully: `go build ./cmd/...`
- [ ] All tests pass: `go test ./...`
- [ ] No compilation errors or warnings
- [ ] TLS/certificate functionality verified (security fixes)
- [ ] Graceful shutdown works correctly (no regressions)

**Priority:** Must Have (CRITICAL - Functionality)

**Verification Steps:**
1. Run `./scripts/00-verify-build.sh --skip-tests`
2. Run `go build ./cmd/...` for all services
3. Run `go test ./...` for all packages
4. Verify TLS connections work correctly

---

### FR-5: Update Local Development Environment

**Description:** Developers should use Go 1.25.5 locally

**User Story:**
> As a developer, I want to use Go 1.25.5 locally so that my development environment matches CI and production.

**Acceptance Criteria:**
- [ ] Documentation provides Go 1.25.5 installation instructions
- [ ] `go version` command shows `go1.25.5` after installation
- [ ] Local builds match CI builds
- [ ] Build verification script checks for Go 1.25.5+

**Priority:** Should Have (Important - Consistency)

**Note:** This is a developer action, not a code change. Documented in FR-3.

---

## 4. Non-Functional Requirements

### NFR-1: Security

**Requirement:** All services must be protected from CVE-2025-61729 and CVE-2025-61727

**Metrics:**
- ✅ Go 1.25.5 includes security patches
- ✅ All Docker images built with Go 1.25.5
- ✅ CI/CD uses Go 1.25.5

**Verification:**
- Check Docker image Go version: `docker run <image> go version`
- Verify CI logs show Go 1.25.5
- Confirm no references to Go 1.23 or Go 1.25 (without patch)

**Priority:** Must Have (CRITICAL)

---

### NFR-2: Backward Compatibility

**Requirement:** Upgrade must be 100% backward compatible

**Metrics:**
- ✅ No breaking changes (patch release)
- ✅ All existing code works without modification
- ✅ No dependency updates required

**Verification:**
- All services build successfully
- All tests pass
- No runtime errors or regressions

**Priority:** Must Have

---

### NFR-3: Consistency

**Requirement:** All environments must use the same Go version

**Metrics:**
- ✅ CI/CD: Go 1.25.5
- ✅ Docker builds: Go 1.25.5
- ✅ Documentation: Go 1.25.5
- ✅ Local development: Go 1.25.5 (recommended)

**Verification:**
- Check all version references in code and docs
- Verify CI workflow uses Go 1.25.5
- Confirm Dockerfile uses Go 1.25.5

**Priority:** Should Have

---

### NFR-4: Build Performance

**Requirement:** Build times should not degrade significantly

**Metrics:**
- Build time increase < 5% (acceptable for security)
- No significant memory usage increase

**Verification:**
- Compare CI build times before/after
- Monitor build resource usage

**Priority:** Nice to Have

---

## 5. User Stories Summary

### Must Have (Security Critical)

1. **US-001: CI/CD Security Update**
   > As an SRE engineer, I want CI/CD to use Go 1.25.5 so that all builds include security patches.
   - **FR:** FR-1
   - **Priority:** CRITICAL

2. **US-002: Production Security Update**
   > As an SRE engineer, I want Docker images built with Go 1.25.5 so that production services include security patches.
   - **FR:** FR-2
   - **Priority:** CRITICAL

3. **US-003: Build Verification**
   > As a developer, I want all services to build successfully with Go 1.25.5 so that I can develop and deploy without issues.
   - **FR:** FR-4
   - **Priority:** CRITICAL

### Should Have (Consistency)

4. **US-004: Documentation Consistency**
   > As a developer, I want documentation to clearly state Go 1.25.5 requirement so that I use the correct version locally.
   - **FR:** FR-3
   - **Priority:** Important

5. **US-005: Local Development Consistency**
   > As a developer, I want to use Go 1.25.5 locally so that my development environment matches CI and production.
   - **FR:** FR-5
   - **Priority:** Important

---

## 6. Acceptance Criteria Summary

### Phase 1: Critical Security Updates (Must Complete)

- [ ] `.github/workflows/build-images.yml` updated to `go-version: '1.25.5'`
- [ ] `services/Dockerfile` updated to `FROM golang:1.25.5-alpine`
- [ ] CI builds succeed with Go 1.25.5
- [ ] All services build successfully: `go build ./cmd/...`
- [ ] Build verification script passes: `./scripts/00-verify-build.sh`

### Phase 2: Documentation Updates (Should Complete)

- [ ] `AGENTS.md` updated with Go 1.25.5 references
- [ ] `README.md` updated with Go 1.25.5 requirement
- [ ] `specs/system-context/06-technology-stack.md` updated
- [ ] `specs/system-context/08-development-workflow.md` updated
- [ ] All version tables show Go 1.25.5

### Phase 3: Verification (Must Complete)

- [ ] All tests pass: `go test ./...`
- [ ] TLS/certificate functionality verified
- [ ] Graceful shutdown verified (no regressions)
- [ ] Docker images built and tested

---

## 7. Success Metrics

### Key Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Security Coverage** | 100% | All services use Go 1.25.5 (CI + Docker) |
| **Build Success Rate** | 100% | All 9 services build successfully |
| **Test Pass Rate** | 100% | All tests pass with Go 1.25.5 |
| **Documentation Consistency** | 100% | All docs reference Go 1.25.5 |
| **Version Consistency** | 100% | CI, Docker, Docs all use 1.25.5 |

### Definition of Done

**Phase 1 (Critical):**
- [ ] CI workflow uses Go 1.25.5
- [ ] Dockerfile uses Go 1.25.5
- [ ] All services build successfully
- [ ] Build verification script passes
- [ ] Security patches applied

**Phase 2 (Documentation):**
- [ ] All documentation updated
- [ ] No references to outdated versions
- [ ] Clear installation instructions

**Phase 3 (Verification):**
- [ ] All tests pass
- [ ] TLS functionality verified
- [ ] No regressions detected
- [ ] Docker images tested

---

## 8. Edge Cases & Error Handling

### Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| **Go 1.25.5 not available in CI** | Use latest 1.25.x patch version available |
| **Docker image golang:1.25.5-alpine not found** | Use `golang:1.25-alpine` (will pull latest 1.25.x) |
| **Local Go version mismatch** | Build verification script warns but doesn't fail |
| **Dependency incompatibility** | All dependencies already compatible (verified in research) |
| **Build failures after upgrade** | Rollback to Go 1.25, investigate issue |

### Error Scenarios

| Error | User Message | System Action |
|-------|--------------|---------------|
| **CI build fails** | "Build failed with Go 1.25.5" | Log error, fail CI build |
| **Docker build fails** | "Docker build failed" | Log error, fail CI build |
| **Test failures** | "Tests failed with Go 1.25.5" | Log test output, fail CI build |
| **Version mismatch** | "Go version mismatch detected" | Warn in build verification script |

### Rollback Plan

**If critical issues occur:**
1. Revert `.github/workflows/build-images.yml` to `go-version: '1.23'`
2. Revert `services/Dockerfile` to `FROM golang:1.25-alpine`
3. Rebuild and redeploy
4. Investigate issue in separate branch
5. Re-apply upgrade after fix

**Rollback Complexity:** LOW - Simple version changes

---

## 9. Out of Scope

The following are explicitly NOT included in this upgrade:

- ❌ **Code improvements** (WaitGroup.Go(), panic reduction) - Separate task
- ❌ **Dependency updates** - Not required, all compatible
- ❌ **Green Tea GC enablement** - Performance optimization, separate task
- ❌ **Structured error types** - Code enhancement, separate task
- ❌ **Test coverage improvements** - Separate task
- ❌ **Migration scripts** - Not needed, direct upgrade
- ❌ **Staging environment testing** - Can be done but not required for patch release

**Rationale:** This is a security patch upgrade. Code improvements and optimizations are separate tasks that can be done later.

---

## 10. Dependencies & Assumptions

### Dependencies

**External:**
- ✅ Go 1.25.5 available in GitHub Actions
- ✅ Docker image `golang:1.25.5-alpine` available
- ✅ All dependencies compatible (verified in research)

**Internal:**
- ✅ Build verification script exists (`scripts/00-verify-build.sh`)
- ✅ CI/CD pipeline functional
- ✅ Docker build process working

### Assumptions

**ASSUME-001: Backward Compatibility**
- **Assumption:** Go 1.25.5 is 100% backward compatible with Go 1.25
- **Validation:** Verified via Go release notes (patch release)
- **Risk:** LOW

**ASSUME-002: Dependency Compatibility**
- **Assumption:** All dependencies work with Go 1.25.5
- **Validation:** All dependencies require Go 1.21+ (verified in research)
- **Risk:** LOW

**ASSUME-003: No Breaking Changes**
- **Assumption:** No code changes required for upgrade
- **Validation:** Patch release, no breaking changes
- **Risk:** LOW

**ASSUME-004: Security Fixes Critical**
- **Assumption:** CVE-2025-61729 and CVE-2025-61727 affect our services
- **Validation:** All services use TLS/certificates
- **Risk:** LOW (assumption is correct)

---

## 11. Implementation Phases

### Phase 1: Critical Security Updates (Day 1)

**Objective:** Apply security patches immediately

**Tasks:**
1. Update `.github/workflows/build-images.yml` → `go-version: '1.25.5'`
2. Update `services/Dockerfile` → `FROM golang:1.25.5-alpine`
3. Run `./scripts/00-verify-build.sh` locally
4. Commit and push changes
5. Verify CI builds succeed

**Estimated Time:** 30 minutes  
**Priority:** CRITICAL

---

### Phase 2: Documentation Updates (Day 1-2)

**Objective:** Ensure documentation consistency

**Tasks:**
1. Update `AGENTS.md` - Go version references
2. Update `README.md` - Go version requirement
3. Update `specs/system-context/06-technology-stack.md`
4. Update `specs/system-context/08-development-workflow.md`
5. Update `specs/active/go125-config-modernization/research.md`

**Estimated Time:** 1-2 hours  
**Priority:** Important

---

### Phase 3: Verification & Testing (Day 2)

**Objective:** Verify upgrade success

**Tasks:**
1. Run `go mod tidy` (verify no changes)
2. Run `./scripts/00-verify-build.sh` (all checks)
3. Build all services: `go build ./cmd/...`
4. Run tests: `go test ./...`
5. Verify TLS/certificate functionality
6. Test graceful shutdown (no regressions)

**Estimated Time:** 1 hour  
**Priority:** CRITICAL

---

## 12. Open Questions

- [ ] **Q1:** Should we enable Green Tea GC in Go 1.25.5?
  - **Answer:** No, separate performance optimization task
  - **Status:** Resolved - Out of scope

- [ ] **Q2:** Should we refactor to use `sync.WaitGroup.Go()`?
  - **Answer:** No, separate code improvement task
  - **Status:** Resolved - Out of scope

- [ ] **Q3:** Do we need staging environment testing?
  - **Answer:** Optional, but recommended for production safety
  - **Status:** Open - Can be done but not required

---

## 13. Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-12-17 | Initial specification for Go 1.25.5 upgrade | AI Assistant |

---

## 14. Next Steps

1. ✅ Review this specification
2. ✅ Resolve open questions (if any)
3. Run `/plan go125-config-modernization` to create technical implementation plan
4. Or run `/implement go125-config-modernization` if ready to execute
5. Execute Phase 1 (Critical Security Updates) immediately

---

*Specification created with SDD 2.0 - Ready for planning and implementation*

