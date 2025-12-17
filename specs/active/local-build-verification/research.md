# Research: Local Build Verification for Go Microservices

**Task ID:** `local-build-verification`  
**Date:** December 17, 2025  
**Status:** Complete

---

## Executive Summary

The project currently lacks local build verification before pushing code to CI. The GitHub Actions workflow has basic lint checks (`go vet`, `gofmt`) but they only run on PRs and use `|| true` to never fail. This allows broken code to reach CI, causing build failures and wasted CI resources.

**Key Findings:**
- CI workflow has lint checks but they don't fail builds
- No local verification scripts exist
- No Makefile for common development tasks
- No pre-commit hooks configured
- Current build errors: unused imports, type errors, duplicate declarations
- AGENTS.md doesn't require local verification

**Recommendation:** Implement a simple build verification script following existing script patterns:
1. **Simple bash script** (`scripts/00-verify-build.sh`) - follows existing numbered script pattern
2. **Basic checks**: `go build`, `go mod tidy`, `go vet`, `gofmt`
3. **Optional git hook** for convenience (not required)
4. **Update AGENTS.md** to require running verification before push

This will catch 90%+ of build errors locally, reduce CI failures, and improve developer workflow. No Makefile needed - keep it simple.

---

## Codebase Analysis

### Existing Patterns

#### 1. GitHub Actions CI Workflow

**Location:** `.github/workflows/build-images.yml`

**Current Implementation:**
```yaml
- name: Run Go lint (PR only)
  if: github.event_name == 'pull_request'
  working-directory: services
  run: |
    echo "Running Go lint for ${{ matrix.service }}..."
    go vet ./cmd/${{ matrix.service }} || true
    gofmt -l ./cmd/${{ matrix.service }} || true
    echo "✓ Lint check completed for ${{ matrix.service }}"
```

**Issues:**
- Only runs on PRs (not on push)
- Uses `|| true` so errors don't fail the build
- Only checks individual services, not the whole codebase
- No `go build` verification before Docker build
- No `go mod tidy` verification
- No `go test` execution

**Reusability:** Can be enhanced to fail properly and run locally

#### 2. Build Scripts Pattern

**Location:** `scripts/05-build-microservices.sh`

**Pattern:**
- Numbered scripts (01-12) for deployment order
- Uses `set -e` for error handling
- Service array for iteration
- Clear echo messages for progress

**Reusability:** Can create `scripts/00-verify-build.sh` following same pattern

#### 3. Dockerfile Build Process

**Location:** `services/Dockerfile`

**Build Command:**
```dockerfile
RUN CGO_ENABLED=0 GOOS=linux go build -o ${SERVICE_NAME} ./cmd/${SERVICE_NAME}
```

**Reusability:** Local verification should use same build flags for consistency

### Reusable Components

1. **Service List**: Already defined in multiple places
   ```bash
   SERVICES=("auth" "user" "product" "cart" "order" "review" "notification" "shipping" "shipping-v2")
   ```

2. **Script Pattern**: Numbered scripts with `set -e` and clear messaging

3. **Working Directory**: `services/` is the Go module root

### Conventions to Follow

1. **Script Naming**: Numbered prefixes (00-12) for execution order
2. **Error Handling**: `set -e` in bash scripts
3. **Service Iteration**: Array-based loops
4. **Clear Output**: Echo messages for each step
5. **Go Module**: All Go code in `services/` directory

---

## External Solutions

### Option 1: Simple Bash Script (Recommended)

**What it is:** Simple bash script following existing script patterns in `scripts/`

**Pros:**
- ✅ Matches existing script pattern (numbered, `set -e`, service arrays)
- ✅ No external dependencies
- ✅ Works offline
- ✅ Easy to understand and maintain
- ✅ Can be run manually: `./scripts/00-verify-build.sh`
- ✅ Can be added to git hook optionally
- ✅ Simple and fast

**Cons:**
- ⚠️ Manual execution (but can be automated with git hook)

**Implementation complexity:** Very Low  
**Team familiarity:** High (same pattern as existing scripts)

**Example Structure:**
```bash
#!/bin/bash
# scripts/00-verify-build.sh

set -e

echo "=== Local Build Verification ==="

cd services

SERVICES=("auth" "user" "product" "cart" "order" "review" "notification" "shipping" "shipping-v2")

echo "1. Running go mod tidy..."
go mod tidy
git diff --exit-code go.mod go.sum || {
    echo "❌ go.mod or go.sum changed. Run 'go mod tidy' and commit changes."
    exit 1
}

echo "2. Checking code formatting..."
if [ -n "$(gofmt -l . | grep -v vendor)" ]; then
    echo "❌ Code not formatted. Run 'gofmt -w .'"
    exit 1
fi

echo "3. Running go vet..."
go vet ./...

echo "4. Building all services..."
for SERVICE in "${SERVICES[@]}"; do
    echo "  Building $SERVICE..."
    go build -o /dev/null ./cmd/$SERVICE
done

echo "✅ All checks passed!"
```

**Optional Git Hook:**
```bash
#!/bin/bash
# .githooks/pre-commit (optional)

./scripts/00-verify-build.sh || {
    echo "❌ Pre-commit checks failed!"
    exit 1
}
```

### Option 2: Pre-commit Framework (Overkill for Simple Build Check)

**What it is:** Python-based framework for managing git hooks with plugins

**Pros:**
- ✅ Large ecosystem of plugins
- ✅ Easy to share configuration (`.pre-commit-config.yaml`)
- ✅ Automatic hook installation
- ✅ Supports multiple languages
- ✅ Can run in CI too

**Cons:**
- ⚠️ Requires Python
- ⚠️ External dependency
- ⚠️ May be overkill for Go-only project
- ⚠️ Slower than native hooks

**Implementation complexity:** Medium  
**Team familiarity:** Medium (popular but not Go-specific)

**Example Config:**
```yaml
repos:
  - repo: https://github.com/dnephin/pre-commit-golang
    rev: v0.5.1
    hooks:
      - id: go-fmt
      - id: go-vet
      - id: go-build
      - id: go-mod-tidy
```

### Option 3: Task Runner (Taskfile/Mage) - Not Needed

**What it is:** Modern task runners as Makefile alternatives

**Pros:**
- ✅ Better syntax than Makefile
- ✅ Cross-platform
- ✅ Built-in features (parallel execution, etc.)

**Cons:**
- ⚠️ External dependency
- ⚠️ Less standard than Makefile
- ⚠️ Team may not be familiar

**Implementation complexity:** Medium  
**Team familiarity:** Low

### Option 4: GitHub Actions Local Runner (act) - Too Complex

**What it is:** Run GitHub Actions workflows locally

**Pros:**
- ✅ Same checks as CI
- ✅ Guaranteed consistency

**Cons:**
- ⚠️ Requires Docker
- ⚠️ Slower than native tools
- ⚠️ Complex setup

**Implementation complexity:** High  
**Team familiarity:** Low

---

## Comparison Matrix

| Criteria | Simple Bash Script | Pre-commit | Task Runner | act |
|----------|-------------------|------------|------------|-----|
| **Setup Complexity** | ⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Speed** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| **Matches Existing Pattern** | ⭐⭐⭐⭐⭐ | ⭐ | ⭐ | ⭐ |
| **No Dependencies** | ⭐⭐⭐⭐⭐ | ⭐ | ⭐⭐ | ⭐ |
| **Ease of Use** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| **Simplicity** | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐ | ⭐ |
| **Maintenance** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |

---

## Recommendations

### Primary Recommendation: Simple Bash Script

**Rationale:**
1. **Matches Existing Pattern**: Follows same pattern as `scripts/05-build-microservices.sh` and other numbered scripts
2. **Zero Dependencies**: No external tools required
3. **Fast**: Native execution, no overhead
4. **Simple**: Easy to understand and maintain - just a bash script
5. **Familiar**: Team already uses this pattern for deployment scripts
6. **No Makefile Needed**: Keep it simple - just run the script

**Implementation Plan:**
1. Create `scripts/00-verify-build.sh` following existing script pattern
2. Use same service array pattern as other scripts
3. Add basic checks: `go mod tidy`, `gofmt`, `go vet`, `go build`
4. Optional: Create `.githooks/pre-commit` for convenience (not required)
5. Add instructions to AGENTS.md to run script before push
6. Update CI to run same checks (can reuse script or inline commands)

**Verification Script Structure:**
```bash
#!/bin/bash
# scripts/00-verify-build.sh

set -e

echo "=== Local Build Verification ==="

cd services

echo "1. Running go mod tidy..."
go mod tidy
git diff --exit-code go.mod go.sum || {
    echo "❌ go.mod or go.sum changed. Run 'go mod tidy' and commit changes."
    exit 1
}

echo "2. Formatting code..."
gofmt -l . | grep -v vendor || true
# Check if any files need formatting
if [ -n "$(gofmt -l . | grep -v vendor)" ]; then
    echo "❌ Code not formatted. Run 'gofmt -w .'"
    exit 1
fi

echo "3. Running go vet..."
go vet ./... || {
    echo "❌ go vet found issues"
    exit 1
}

echo "4. Building all services..."
SERVICES=("auth" "user" "product" "cart" "order" "review" "notification" "shipping" "shipping-v2")
for SERVICE in "${SERVICES[@]}"; do
    echo "  Building $SERVICE..."
    go build -o /dev/null ./cmd/$SERVICE || {
        echo "❌ Failed to build $SERVICE"
        exit 1
    }
done

echo "5. Running tests..."
go test ./... || {
    echo "❌ Tests failed"
    exit 1
}

echo "✅ All checks passed!"
```

### Alternative Approach: Just Run Script Manually

**When to use:** If git hooks are not desired

**Trade-off:** Manual execution but maximum simplicity - just run `./scripts/00-verify-build.sh` before pushing

---

## Open Questions

1. **Test Coverage**: Should verification include test coverage checks?
   - **Recommendation**: Start without, add later if needed

2. **Linter Choice**: Use `golangci-lint` or stick with `go vet`?
   - **Recommendation**: Start with `go vet` (simple, built-in), upgrade to `golangci-lint` later if needed

3. **CI Integration**: Should CI use same script or inline commands?
   - **Recommendation**: Can reuse script or inline same commands - both work

4. **Hook Enforcement**: Make hooks mandatory or optional?
   - **Recommendation**: Optional but documented (can be bypassed with `--no-verify`)

5. **Script Numbering**: Should verification script be `00-` or separate from deployment scripts?
   - **Recommendation**: Use `00-` to indicate it runs before deployment (matches existing pattern)

---

## Current Build Errors to Fix

Based on recent build attempts, these errors need fixing:

1. **Unused Import**: `internal/notification/logic/v1/service.go`
   - `database/sql` imported but not used

2. **Type Error**: `internal/product/logic/v1/service.go`
   - `product.ID` (string) used as interface incorrectly

3. **Duplicate Declaration**: `internal/review/logic/v1/errors.go`
   - `ErrDuplicateReview` declared twice

**Action Required:** Fix these before implementing verification (or verification will catch them)

---

## Next Steps

1. ✅ **Research Complete** - Patterns and options documented
2. **Review findings** with team
3. **Run `/specify local-build-verification`** to define requirements
4. **Run `/plan local-build-verification`** to create implementation plan
5. **Fix current build errors** (unused imports, type errors, duplicates)
6. **Implement simple verification script** (`scripts/00-verify-build.sh`)
7. **Update AGENTS.md** with verification requirements (run script before push)
8. **Update CI workflow** to use same checks (can reuse script or inline)

---

## References

- [Go Best Practices - Makefiles](https://github.com/golang-standards/project-layout)
- [Pre-commit Framework](https://pre-commit.com/)
- [Git Hooks Documentation](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)
- [golangci-lint](https://golangci-lint.run/) (for future consideration)

---

*Research completed with SDD 2.0*

