# Specification: Local Build Verification Script

**Task ID:** `local-build-verification`  
**Created:** December 17, 2025  
**Status:** Ready for Planning  
**Version:** 1.1

---

## 1. Problem Statement

### The Problem
Developers push code to CI without verifying it builds locally first. The GitHub Actions workflow has lint checks but they use `|| true` and don't fail builds, allowing broken code to reach CI. This causes:
- Build failures in CI that waste resources and time
- Developer frustration from waiting for CI only to discover simple errors
- Reduced confidence in code quality before merging

### Current Situation
- No local verification script exists
- CI has basic checks (`go vet`, `gofmt`) but they don't fail builds
- Developers discover build errors only after pushing and waiting for CI
- Common errors: missing go.sum entries, import path issues, compilation errors
- AGENTS.md doesn't require local verification before push

### Desired Outcome
Developers run a simple script (`./scripts/00-verify-build.sh`) before pushing code. The script catches 90%+ of build errors locally, reducing CI failures and improving developer workflow. The script follows existing script patterns (numbered, `set -e`, service arrays) and requires no external dependencies.

---

## 2. User Personas

### Primary User: Developer
- **Who:** Go developers working on microservices
- **Goals:** 
  - Verify code builds before pushing
  - Catch errors quickly without waiting for CI
  - Follow simple, familiar workflow
- **Pain points:** 
  - Wasting time on CI failures from simple errors
  - Not knowing if code compiles before pushing
  - No clear guidance on what to check
- **Tech comfort:** High (familiar with bash scripts, Go toolchain)

### Secondary User: CI/CD System
- **Who:** GitHub Actions workflow
- **Goals:** 
  - Reuse same verification logic for consistency
  - Reduce failed builds from preventable errors
- **Pain points:** 
  - Running expensive builds that fail on simple errors
  - Inconsistent checks between local and CI
- **Tech comfort:** N/A (automated system)

---

## 3. Functional Requirements

### FR-1: Build Verification Script

**Description:** Create a bash script `scripts/00-verify-build.sh` that verifies Go code builds correctly before pushing to CI.

**User Story:**
> As a developer, I want to run a simple script that checks if my code builds, so that I catch errors before pushing to CI.

**Acceptance Criteria:**
- [ ] Script exists at `scripts/00-verify-build.sh`
- [ ] Script follows existing pattern: `#!/bin/bash`, `set -e`, numbered prefix (00-)
- [ ] Script can be executed: `./scripts/00-verify-build.sh`
- [ ] Script exits with code 0 on success, non-zero on failure
- [ ] Script provides clear error messages for each failure
- [ ] Script completes in < 30 seconds for all 9 services

**Priority:** Must Have

### FR-2: Go Module Verification

**Description:** Verify `go.mod` and `go.sum` are up to date and consistent.

**User Story:**
> As a developer, I want the script to check if `go.mod` and `go.sum` are synchronized, so that I don't push missing dependencies.

**Acceptance Criteria:**
- [ ] Script runs `go mod tidy` to ensure dependencies are correct
- [ ] Script checks if `go.mod` or `go.sum` changed after `go mod tidy`
- [ ] If files changed, script fails with clear message: "go.mod or go.sum changed. Run 'go mod tidy' and commit changes."
- [ ] Script uses `git diff --exit-code` to detect changes
- [ ] Check happens before build to catch dependency issues early

**Priority:** Must Have

### FR-3: Code Formatting Check

**Description:** Verify code follows Go formatting standards using `gofmt`.

**User Story:**
> As a developer, I want the script to check if my code is properly formatted, so that I maintain consistent code style.

**Acceptance Criteria:**
- [ ] Script runs `gofmt -l .` to find unformatted files
- [ ] Script excludes vendor directory from check
- [ ] If unformatted files found, script fails with message: "Code not formatted. Run 'gofmt -w .'"
- [ ] Script lists which files need formatting (optional but helpful)
- [ ] Check is fast (< 5 seconds)

**Priority:** Must Have

### FR-4: Static Analysis Check

**Description:** Run `go vet` to catch common Go code issues.

**User Story:**
> As a developer, I want the script to run static analysis, so that I catch potential bugs before they reach CI.

**Acceptance Criteria:**
- [ ] Script runs `go vet ./...` on entire codebase
- [ ] Script fails if `go vet` reports any issues
- [ ] Script displays `go vet` output for debugging
- [ ] Check covers all packages (not just cmd/)
- [ ] Check completes in < 10 seconds

**Priority:** Must Have

### FR-5: Build All Services

**Description:** Verify all 9 microservices compile successfully.

**User Story:**
> As a developer, I want the script to build all services, so that I know my changes don't break any service.

**Acceptance Criteria:**
- [ ] Script builds all 9 services: auth, user, product, cart, order, review, notification, shipping, shipping-v2
- [ ] Script uses service array pattern: `SERVICES=("auth" "user" ...)`
- [ ] Script builds each service: `go build -o /dev/null ./cmd/$SERVICE`
- [ ] Script shows progress: "Building $SERVICE..."
- [ ] Script fails fast on first build error
- [ ] Build uses same flags as Dockerfile: `CGO_ENABLED=0 GOOS=linux` (optional, for consistency)
- [ ] All builds complete in < 20 seconds

**Priority:** Must Have

### FR-6: Test Execution (Optional)

**Description:** Run tests to verify code correctness.

**User Story:**
> As a developer, I want the script to run tests, so that I catch test failures before pushing.

**Acceptance Criteria:**
- [ ] Script runs `go test ./...` on entire codebase
- [ ] Script fails if any test fails
- [ ] Script shows test output for debugging
- [ ] Tests run after build (build must succeed first)
- [ ] Test execution is optional (can be skipped with flag or separate script)

**Priority:** Should Have

### FR-7: Clear Output and Error Messages

**Description:** Script provides clear, actionable feedback to developers.

**User Story:**
> As a developer, I want clear error messages, so that I know exactly what to fix.

**Acceptance Criteria:**
- [ ] Script shows progress for each step: "1. Running go mod tidy...", "2. Checking code formatting..."
- [ ] Script shows success message: "✅ All checks passed!"
- [ ] Error messages are specific: "❌ Failed to build auth" not just "Build failed"
- [ ] Error messages include fix instructions: "Run 'gofmt -w .'" not just "Formatting error"
- [ ] Script uses consistent formatting: `=== Section ===` for major sections

**Priority:** Must Have

### FR-8: AGENTS.md Documentation

**Description:** Update AGENTS.md to require running verification script before push.

**User Story:**
> As a developer, I want clear documentation on when to run the verification script, so that I follow best practices.

**Acceptance Criteria:**
- [ ] AGENTS.md includes section on local build verification
- [ ] Documentation explains when to run script (before push, before PR)
- [ ] Documentation shows example: `./scripts/00-verify-build.sh`
- [ ] Documentation explains what the script checks
- [ ] Documentation links to troubleshooting if script fails

**Priority:** Must Have

---

## 4. Non-Functional Requirements

### NFR-1: Performance
- Script must complete all checks in < 30 seconds for all 9 services
- Individual checks should be fast:
  - `go mod tidy`: < 5 seconds
  - `gofmt -l`: < 5 seconds
  - `go vet`: < 10 seconds
  - `go build` (all services): < 20 seconds
- Script should fail fast (stop on first error)

### NFR-2: Compatibility
- Script must work on macOS, Linux (CI environment)
- Script must work with Go 1.25.5 (current version)
- Script must follow existing script patterns (numbered, `set -e`, service arrays)
- Script must be compatible with existing CI workflow

### NFR-3: Maintainability
- Script must be simple and easy to understand (< 100 lines)
- Script must follow existing conventions (same as `scripts/05-build-microservices.sh`)
- Script must have clear comments explaining each check
- Script must be easy to extend with additional checks

### NFR-4: Reliability
- Script must use `set -e` to fail on any error
- Script must handle edge cases (no git repo, missing Go, etc.)
- Script must provide clear error messages for all failure modes
- Script must not modify files (read-only checks, except `go mod tidy` which is verified)

---

## 5. Out of Scope

The following are explicitly NOT included in this feature:

- ❌ **Test Coverage Requirements** - Not checking coverage thresholds, just running tests
- ❌ **Complex Linters** - No `golangci-lint` or other external linters (keep it simple)
- ❌ **Auto-fix Functionality** - Script checks but doesn't fix (e.g., doesn't run `gofmt -w`)
- ❌ **Git Hook Enforcement** - Git hooks are optional convenience, not required
- ❌ **Makefile Integration** - No Makefile needed, just a simple bash script
- ❌ **Docker Build Verification** - Only Go build, not Docker image build
- ❌ **Performance Benchmarks** - Not checking execution time or memory usage
- ❌ **Security Scanning** - No vulnerability scanning (focus on build correctness)

---

## 6. Edge Cases & Error Handling

### Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Script run outside git repository | Fail with clear message: "Not in a git repository. Run from project root." |
| Script run from wrong directory | Fail with clear message: "services/ directory not found. Run from project root." |
| Go not installed | Fail with clear message: "Go not found. Install Go 1.25.5+." |
| Go version mismatch | Warn but continue (Go 1.25.5+ required, but don't fail on minor version differences) |
| No changes to go.mod/go.sum | Pass check (git diff returns success) |
| All files already formatted | Pass check (gofmt -l returns empty) |
| No tests in codebase | Pass test check (go test returns success with no tests) |
| Partial service build failure | Fail fast on first error, show which service failed |
| Network issues during go mod download | Fail with clear message about network error |

### Error Scenarios

| Error | User Message | System Action |
|-------|--------------|---------------|
| `go mod tidy` changes files | "❌ go.mod or go.sum changed. Run 'go mod tidy' and commit changes." | Exit 1 |
| Unformatted code found | "❌ Code not formatted. Run 'gofmt -w .'" | Exit 1 |
| `go vet` finds issues | "❌ go vet found issues: [output]" | Exit 1 |
| Service build fails | "❌ Failed to build $SERVICE: [error]" | Exit 1 |
| Test failure | "❌ Tests failed: [output]" | Exit 1 |
| Missing services directory | "❌ services/ directory not found. Run from project root." | Exit 1 |
| Go not installed | "❌ Go not found. Install Go 1.25.5+." | Exit 1 |

---

## 7. Success Metrics

### Key Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Build Error Catch Rate** | 90%+ | Compare CI failures before/after script adoption |
| **CI Failure Reduction** | 50%+ | Track failed CI builds per week |
| **Script Execution Time** | < 30 seconds | Time script execution for all checks |
| **Developer Adoption** | 80%+ | Survey or track script usage (optional) |
| **False Positives** | < 5% | Script failures that are not actual errors |

### Definition of Done

- [ ] Script created at `scripts/00-verify-build.sh`
- [ ] All acceptance criteria met for FR-1 through FR-7
- [ ] Script follows existing script patterns
- [ ] Script completes in < 30 seconds
- [ ] All edge cases handled with clear error messages
- [ ] AGENTS.md updated with verification requirements
- [ ] Script tested on macOS and Linux
- [ ] Script verified with all 9 services
- [ ] Documentation clear and complete

---

## 8. Open Questions

- [ ] **Test Execution**: Should tests be mandatory or optional? (Recommendation: Optional, can add `--skip-tests` flag)
- [ ] **CI Integration**: Should CI workflow use the script directly or inline the same commands? (Recommendation: Either works, inline might be simpler for CI)
- [ ] **Git Hook**: Should we provide a sample git hook or just document it? (Recommendation: Provide sample in `.githooks/pre-commit` but mark as optional)
- [ ] **Build Flags**: Should local build use same flags as Dockerfile (`CGO_ENABLED=0 GOOS=linux`)? (Recommendation: Optional, can add for consistency)

---

## 9. Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.1 | 2025-12-17 | [REFINED] Updated Go version references to 1.25.5 | System |
| 1.0 | 2025-12-17 | Initial specification | AI Agent |

---

## Next Steps

1. ✅ Review specification with stakeholders
2. Resolve 4 open questions
3. Run `/plan local-build-verification` to create technical implementation plan
4. Run `/tasks local-build-verification` to break down into actionable tasks

---

*Specification created with SDD 2.0*

