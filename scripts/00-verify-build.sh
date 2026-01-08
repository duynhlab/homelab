#!/bin/bash
set -e

echo "=== Independent Service Build Verification ==="

# Create bin directory if it doesn't exist
mkdir -p bin

# Verify each service independently
for service_dir in services/*/; do
    if [ ! -f "$service_dir/go.mod" ]; then
        continue
    fi
    
    service=$(basename "$service_dir")
    echo ""
    echo "=== Verifying $service (as independent repo) ==="
    
    cd "$service_dir"
    
    # 1. Format check
    echo "  1. Checking formatting..."
    unformatted=$(gofmt -l . 2>/dev/null || true)
    if [ -n "$unformatted" ]; then
        echo "  ERROR: Unformatted files:"
        echo "$unformatted"
        exit 1
    fi
    echo "  Code formatted"
    
    # 2. Module verification
    echo "  2. Running go mod tidy..."
    go mod tidy
    go mod verify
    echo "  Modules OK"
    
    # 3. Build binary (CRITICAL - must succeed)
    echo "  3. Building binary..."
    if [ -f "cmd/main.go" ]; then
        go build -o ../../bin/$service ./cmd/main.go
        echo "  Binary built: bin/$service"
    else
        echo "  WARNING: No cmd/main.go found, skipping binary build"
    fi
    
    # 4. Vet
    echo "  4. Running go vet..."
    go vet ./...
    echo "  go vet passed"
    
    echo "  $service verified (independent)"
    cd ../..
done

echo ""
echo "=== All services verified ==="
echo ""
echo "Built binaries:"
ls -lh bin/ 2>/dev/null || echo "No binaries built"
