# Technical Plan: Local Build Verification Script

**Task ID:** `local-build-verification`  
**Created:** December 17, 2025  
**Status:** Ready for Implementation  
**Based on:** spec.md v1.1  
**Version:** 1.1

---

## 1. System Architecture

### Overview

Simple linear bash script that executes sequential verification checks. No complex architecture needed - just a straightforward script following existing patterns.

```
┌─────────────────────────────────────┐
│  scripts/00-verify-build.sh          │
│  ┌───────────────────────────────┐  │
│  │ 1. Environment Validation     │  │
│  │    - Check Go installed       │  │
│  │    - Check git repo           │  │
│  │    - Check services/ exists   │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 2. Go Module Check            │  │
│  │    - go mod tidy              │  │
│  │    - git diff go.mod go.sum   │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 3. Formatting Check            │  │
│  │    - gofmt -l .                │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 4. Static Analysis             │  │
│  │    - go vet ./...              │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 5. Build All Services          │  │
│  │    - Loop through SERVICES[]   │  │
│  │    - go build ./cmd/$SERVICE   │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 6. Tests (Optional)            │  │
│  │    - go test ./...             │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │ 7. Success Message             │  │
│  │    - ✅ All checks passed!     │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Script Type** | Bash script | Matches existing script pattern, no dependencies |
| **Execution Model** | Sequential, fail-fast | Simple, clear error reporting, fast feedback |
| **Error Handling** | `set -e` + explicit checks | Follows existing pattern, reliable failure detection |
| **Service Iteration** | Array-based loop | Matches `scripts/05-build-microservices.sh` pattern |
| **Output Format** | Echo with emoji indicators | Clear, visual feedback (✅/❌) |
| **Test Execution** | Optional flag | Tests can be slow, make them optional |
| **Git Hook** | Optional convenience | Not required, but helpful for developers |

---

## 2. Technology Stack

| Layer | Technology | Version | Rationale |
|-------|------------|---------|-----------|
| **Scripting** | Bash | POSIX-compliant | Standard, works on macOS/Linux, no dependencies |
| **Build Tool** | Go | 1.25.5+ | Current project version, required for all checks |
| **Version Control** | Git | Any | Used for detecting go.mod/go.sum changes |
| **Platform** | macOS, Linux | - | Developer machines and CI environment |

### Dependencies

**Required:**
- Bash shell (standard on macOS/Linux)
- Go 1.25.5+ toolchain
- Git (for change detection)

**Optional:**
- Git hooks support (for convenience)

**No external dependencies** - keeps it simple and fast.

---

## 3. Script Design

### Component 1: Verification Script (`scripts/00-verify-build.sh`)

**Purpose:** Main script that executes all verification checks

**Structure:**
```bash
#!/bin/bash
set -e

# Header
echo "=== Local Build Verification ==="

# Service array (matches existing pattern)
SERVICES=("auth" "user" "product" "cart" "order" "review" "notification" "shipping" "shipping-v2")

# Environment validation
# - Check Go installed
# - Check git repo
# - Check services/ directory

# Sequential checks
# 1. Go module verification
# 2. Code formatting
# 3. Static analysis
# 4. Build all services
# 5. Optional tests

# Success message
echo "✅ All checks passed!"
```

**Responsibilities:**
- Validate environment (Go, git, directory structure)
- Execute checks in order (fail fast)
- Provide clear error messages
- Exit with appropriate codes (0 = success, 1 = failure)

**Dependencies:** 
- Go toolchain installed
- Git repository initialized
- `services/` directory exists

**Key Functions:**
```bash
# Environment validation
check_environment() {
  # Check Go
  # Check git
  # Check directory
}

# Go module check
check_go_modules() {
  go mod tidy
  git diff --exit-code go.mod go.sum || {
    echo "❌ go.mod or go.sum changed..."
    exit 1
  }
}

# Formatting check
check_formatting() {
  if [ -n "$(gofmt -l . | grep -v vendor)" ]; then
    echo "❌ Code not formatted..."
    exit 1
  fi
}

# Static analysis
check_static_analysis() {
  go vet ./... || {
    echo "❌ go vet found issues..."
    exit 1
  }
}

# Build services
build_services() {
  for SERVICE in "${SERVICES[@]}"; do
    go build -o /dev/null ./cmd/$SERVICE || {
      echo "❌ Failed to build $SERVICE..."
      exit 1
    }
  done
}
```

### Component 2: Optional Git Hook (`.githooks/pre-commit`)

**Purpose:** Convenience wrapper to run verification before commit

**Structure:**
```bash
#!/bin/bash
# .githooks/pre-commit

./scripts/00-verify-build.sh || {
    echo "❌ Pre-commit checks failed!"
    exit 1
}
```

**Responsibilities:**
- Call verification script
- Fail commit if checks fail
- Provide clear feedback

**Dependencies:** 
- Verification script exists
- Git hooks enabled (developer setup)

**Note:** Optional - not required, just convenience

### Component 3: Documentation Update (AGENTS.md)

**Purpose:** Document verification requirements and usage

**Location:** `AGENTS.md` (add new section)

**Content:**
- When to run script (before push, before PR)
- How to run: `./scripts/00-verify-build.sh`
- What checks are performed
- Troubleshooting common issues
- Optional git hook setup

---

## 4. Check Implementation Details

### Check 1: Environment Validation

**Purpose:** Ensure prerequisites are met

**Implementation:**
```bash
# Check Go installed
if ! command -v go &> /dev/null; then
    echo "❌ Go not found. Install Go 1.25.5+."
    exit 1
fi

# Check git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ Not in a git repository. Run from project root."
    exit 1
fi

# Check services directory
if [ ! -d "services" ]; then
    echo "❌ services/ directory not found. Run from project root."
    exit 1
fi
```

**Error Handling:** Fail fast with clear message

**Performance:** < 1 second

### Check 2: Go Module Verification

**Purpose:** Ensure go.mod and go.sum are synchronized

**Implementation:**
```bash
cd services

echo "1. Running go mod tidy..."
go mod tidy

# Check if files changed
if ! git diff --exit-code go.mod go.sum > /dev/null; then
    echo "❌ go.mod or go.sum changed. Run 'go mod tidy' and commit changes."
    exit 1
fi
```

**Error Handling:** 
- Network errors during `go mod tidy` will fail naturally (set -e)
- File changes detected via git diff

**Performance:** < 5 seconds

**Edge Cases:**
- No git repo: Handled in environment validation
- Files already committed: git diff returns success
- Network issues: go mod tidy fails, script exits

### Check 3: Code Formatting

**Purpose:** Verify code follows Go formatting standards

**Implementation:**
```bash
echo "2. Checking code formatting..."
UNFORMATTED=$(gofmt -l . | grep -v vendor || true)

if [ -n "$UNFORMATTED" ]; then
    echo "❌ Code not formatted. Run 'gofmt -w .'"
    echo "Files needing formatting:"
    echo "$UNFORMATTED"
    exit 1
fi
```

**Error Handling:**
- List unformatted files for developer
- Provide fix instruction

**Performance:** < 5 seconds

**Edge Cases:**
- All files formatted: Empty output, check passes
- Vendor directory: Excluded via grep -v

### Check 4: Static Analysis

**Purpose:** Catch common Go code issues

**Implementation:**
```bash
echo "3. Running go vet..."
if ! go vet ./...; then
    echo "❌ go vet found issues"
    exit 1
fi
```

**Error Handling:**
- go vet output displayed automatically
- Fail on any issues

**Performance:** < 10 seconds

**Edge Cases:**
- No issues: go vet returns success
- Multiple issues: All reported, script fails

### Check 5: Build All Services

**Purpose:** Verify all services compile

**Implementation:**
```bash
echo "4. Building all services..."
for SERVICE in "${SERVICES[@]}"; do
    echo "  Building $SERVICE..."
    if ! go build -o /dev/null ./cmd/$SERVICE; then
        echo "❌ Failed to build $SERVICE"
        exit 1
    fi
done
```

**Error Handling:**
- Fail fast on first build error
- Show which service failed
- Build output captured (go build shows errors)

**Performance:** < 20 seconds for all 9 services

**Edge Cases:**
- Service doesn't exist: go build fails, script exits
- Partial compilation: Fail on first error
- Build flags: Optional - can add `CGO_ENABLED=0 GOOS=linux` for consistency

### Check 6: Tests (Optional)

**Purpose:** Run tests to verify correctness

**Implementation:**
```bash
# Check for --skip-tests flag
SKIP_TESTS=false
for arg in "$@"; do
    if [ "$arg" = "--skip-tests" ]; then
        SKIP_TESTS=true
        break
    fi
done

if [ "$SKIP_TESTS" = "false" ]; then
    echo "5. Running tests..."
    if ! go test ./...; then
        echo "❌ Tests failed"
        exit 1
    fi
else
    echo "5. Skipping tests (--skip-tests flag)"
fi
```

**Error Handling:**
- Test output displayed
- Fail on any test failure
- Can be skipped with flag

**Performance:** Variable (depends on test suite)

**Edge Cases:**
- No tests: go test returns success
- Test timeout: Handled by go test
- Skip flag: Check command line args

---

## 5. Error Handling Strategy

### Error Detection

**Primary Method:** `set -e`
- Script exits immediately on any command failure
- No need for explicit error checking on every command

**Explicit Checks:**
- Environment validation (Go, git, directory)
- File change detection (git diff)
- Formatting check (gofmt output)

### Error Messages

**Format:** `❌ [Check Name]: [Specific Error]`

**Examples:**
- `❌ Go not found. Install Go 1.25.5+.`
- `❌ go.mod or go.sum changed. Run 'go mod tidy' and commit changes.`
- `❌ Code not formatted. Run 'gofmt -w .'`
- `❌ Failed to build auth`

**Best Practices:**
- Specific: Mention exact service/file that failed
- Actionable: Include fix instruction
- Clear: Use emoji indicators (✅/❌)

### Exit Codes

- `0`: All checks passed
- `1`: Any check failed
- Script uses `set -e` so any command failure = exit 1

### Edge Case Handling

| Edge Case | Handling Strategy |
|-----------|-------------------|
| Script run outside git repo | Environment check fails early |
| Script run from wrong directory | Directory check fails early |
| Go not installed | Environment check fails early |
| Network issues during go mod download | `go mod tidy` fails, script exits |
| No changes to go.mod/go.sum | git diff succeeds, check passes |
| All files formatted | gofmt returns empty, check passes |
| No tests | go test succeeds with no tests |

---

## 6. Integration Points

### Integration 1: AGENTS.md Documentation

**Location:** `AGENTS.md` - Add new section

**Content Structure:**
```markdown
### Local Build Verification

**Before pushing code, run:**
```bash
./scripts/00-verify-build.sh
```

**What it checks:**
1. Go module synchronization (go.mod/go.sum)
2. Code formatting (gofmt)
3. Static analysis (go vet)
4. Build all services
5. Tests (optional)

**If script fails:**
- Fix the reported error
- Re-run the script
- Commit changes only after all checks pass

**Optional: Git Hook Setup**
[Instructions for optional git hook]
```

**Update Location:** After "Common Workflows" section, before "Command Reference"

### Integration 2: CI Workflow

**Location:** `.github/workflows/build-images.yml`

**Current State:** Has lint checks but they use `|| true` and don't fail

**Options:**
1. **Reuse Script:** Call `./scripts/00-verify-build.sh` in CI
2. **Inline Commands:** Use same commands inline (simpler for CI)

**Recommendation:** Inline commands for CI (no need to checkout script, just run commands)

**Implementation:**
```yaml
- name: Verify build
  working-directory: services
  run: |
    go mod tidy
    git diff --exit-code go.mod go.sum || exit 1
    gofmt -l . | grep -v vendor || exit 1
    go vet ./...
    go build ./cmd/auth ./cmd/user ...
```

### Integration 3: Optional Git Hook

**Location:** `.githooks/pre-commit`

**Purpose:** Run verification automatically before commit

**Setup Instructions:**
```bash
# Install git hook
cp .githooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

**Note:** Optional - developers can skip with `git commit --no-verify`

---

## 7. Testing Strategy

### Unit Testing (Manual)

**Test Cases:**

1. **Happy Path:**
   - All checks pass
   - Script exits with code 0
   - Success message displayed

2. **Go Module Changes:**
   - Modify go.mod manually
   - Run script
   - Should fail with clear message

3. **Unformatted Code:**
   - Add unformatted Go file
   - Run script
   - Should fail and list file

4. **Build Failure:**
   - Introduce syntax error in service
   - Run script
   - Should fail on that service

5. **Environment Validation:**
   - Run from wrong directory
   - Should fail early with clear message

6. **Test Execution:**
   - Run with `--skip-tests`
   - Tests should be skipped
   - Run without flag
   - Tests should execute

### Platform Testing

**Test on:**
- macOS (developer machines)
- Linux (CI environment)

**Verify:**
- Script executes correctly
- All checks work
- Error messages clear
- Performance targets met (< 30 seconds)

### Integration Testing

**Test with:**
- All 9 services present
- All services building successfully
- Various error scenarios
- Git repository present
- Go 1.25.5+ installed

---

## 8. Implementation Phases

### Phase 1: Core Script (Day 1)

**Tasks:**
- [ ] Create `scripts/00-verify-build.sh` with header
- [ ] Add environment validation
- [ ] Implement go module check
- [ ] Implement formatting check
- [ ] Implement static analysis check
- [ ] Implement build all services
- [ ] Add success message

**Deliverable:** Working script with all must-have checks

**Testing:** Manual testing on macOS

### Phase 2: Error Handling & Edge Cases (Day 1)

**Tasks:**
- [ ] Add comprehensive error messages
- [ ] Handle edge cases (wrong directory, missing Go, etc.)
- [ ] Test all error scenarios
- [ ] Verify exit codes

**Deliverable:** Robust error handling

**Testing:** Test all edge cases

### Phase 3: Optional Features (Day 1)

**Tasks:**
- [ ] Add optional test execution with `--skip-tests` flag
- [ ] Create optional git hook (`.githooks/pre-commit`)
- [ ] Add git hook setup instructions

**Deliverable:** Optional features complete

**Testing:** Test with and without flag

### Phase 4: Documentation (Day 1)

**Tasks:**
- [ ] Update AGENTS.md with verification section
- [ ] Add usage instructions
- [ ] Add troubleshooting guide
- [ ] Document optional git hook setup

**Deliverable:** Complete documentation

**Testing:** Review documentation clarity

### Phase 5: CI Integration (Day 1-2)

**Tasks:**
- [ ] Update CI workflow to use same checks
- [ ] Remove `|| true` from lint checks
- [ ] Make CI checks fail properly
- [ ] Test CI workflow

**Deliverable:** CI uses same verification logic

**Testing:** Test CI workflow with failing checks

### Phase 6: Validation & Polish (Day 2)

**Tasks:**
- [ ] Test on Linux (CI environment)
- [ ] Verify performance (< 30 seconds)
- [ ] Test with all 9 services
- [ ] Fix any issues found
- [ ] Final documentation review

**Deliverable:** Production-ready script

**Testing:** Full validation on both platforms

---

## 9. Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| **Script too slow** | Medium | Low | Performance targets set (< 30s), can optimize if needed |
| **False positives** | Low | Medium | Clear error messages help developers understand issues |
| **Platform differences** | Medium | Low | Test on both macOS and Linux, use POSIX-compliant bash |
| **Go version mismatch** | Low | Low | Check Go version in environment validation, warn if needed |
| **Network issues** | Low | Low | `go mod tidy` will fail naturally, clear error message |
| **Developer adoption** | Medium | Medium | Clear documentation, optional git hook for convenience |
| **CI integration issues** | Medium | Low | Test CI workflow thoroughly, can inline commands if script fails |

### Risk Mitigation Strategies

1. **Performance:** Set clear targets, monitor execution time, optimize if needed
2. **False Positives:** Provide clear, actionable error messages
3. **Platform Issues:** Test on both platforms, use standard bash features
4. **Adoption:** Make it easy (simple script), document clearly, provide git hook option

---

## 10. Open Questions

- [x] **Test Execution**: Optional with `--skip-tests` flag (decided)
- [x] **CI Integration**: Inline commands in CI workflow (decided - simpler)
- [x] **Git Hook**: Provide sample but mark as optional (decided)
- [ ] **Build Flags**: Should we use `CGO_ENABLED=0 GOOS=linux` for consistency with Dockerfile? (Recommendation: Optional, can add later if needed)

---

## 11. Success Criteria

### Technical Success

- [ ] Script executes all checks in < 30 seconds
- [ ] All 9 services build successfully
- [ ] Error messages are clear and actionable
- [ ] Script works on macOS and Linux
- [ ] All edge cases handled

### Process Success

- [ ] AGENTS.md updated with clear instructions
- [ ] Developers can run script easily
- [ ] CI workflow uses same checks
- [ ] Documentation complete

### Business Success

- [ ] 90%+ of build errors caught locally
- [ ] 50%+ reduction in CI failures
- [ ] Developer satisfaction improved

---

## Next Steps

1. ✅ Review technical plan
2. Run `/tasks local-build-verification` to generate implementation tasks
3. Run `/implement local-build-verification` to start building
4. Test script on macOS and Linux
5. Update CI workflow
6. Update documentation

---

*Plan created with SDD 2.0*

