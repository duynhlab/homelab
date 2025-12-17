#!/bin/bash
set -e

echo "=== Local Build Verification ==="

# Service names (matches existing script pattern)
SERVICES=(
    "auth"
    "user"
    "product"
    "cart"
    "order"
    "review"
    "notification"
    "shipping"
    "shipping-v2"
)

# Check for --skip-tests flag
SKIP_TESTS=false
for arg in "$@"; do
    if [ "$arg" = "--skip-tests" ]; then
        SKIP_TESTS=true
        break
    fi
done

# Environment validation
echo ""
echo "Checking environment..."

# Check Go installed
if ! command -v go &> /dev/null; then
    echo "ERROR: Go not found. Install Go 1.25.5+."
    exit 1
fi

# Check git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: Not in a git repository. Run from project root."
    exit 1
fi

# Check services directory
if [ ! -d "services" ]; then
    echo "ERROR: services/ directory not found. Run from project root."
    exit 1
fi

echo "✓ Environment OK"
echo ""

# Change to services directory
cd services

# Check 1: Go Module Verification
echo "1. Running go mod tidy..."
go mod tidy

# Check if go.mod or go.sum changed
if ! git diff --exit-code go.mod go.sum > /dev/null 2>&1; then
    echo "ERROR: go.mod or go.sum changed. Run 'go mod tidy' and commit changes."
    exit 1
fi
echo "✓ Go modules OK"

# Check 2: Code Formatting
echo ""
echo "2. Checking code formatting..."
UNFORMATTED=$(gofmt -l . | grep -v vendor || true)

if [ -n "$UNFORMATTED" ]; then
    echo "ERROR: Code not formatted. Run 'gofmt -w .'"
    echo "Files needing formatting:"
    echo "$UNFORMATTED"
    exit 1
fi
echo "✓ Code formatting OK"

# Check 3: Static Analysis
echo ""
echo "3. Running go vet..."
if ! go vet ./...; then
    echo "ERROR: go vet found issues"
    exit 1
fi
echo "✓ Static analysis OK"

# Check 4: Build All Services
echo ""
echo "4. Building all services..."
for SERVICE in "${SERVICES[@]}"; do
    echo "  Building $SERVICE..."
    if ! go build -o /dev/null ./cmd/$SERVICE; then
        echo "ERROR: Failed to build $SERVICE"
        exit 1
    fi
done
echo "✓ All services build OK"

# Check 5: Tests (Optional)
echo ""
if [ "$SKIP_TESTS" = "false" ]; then
    echo "5. Running tests..."
    if ! go test ./...; then
        echo "ERROR: Tests failed"
        exit 1
    fi
    echo "✓ Tests OK"
else
    echo "5. Skipping tests (--skip-tests flag)"
fi

# Success
echo ""
echo "SUCCESS: All checks passed!"

