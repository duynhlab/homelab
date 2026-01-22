#!/bin/bash
# Build all Go services locally (no Docker)
set -e

export PATH=$PATH:/usr/local/go/bin
echo "=== Building all services ==="
mkdir -p bin

for service_dir in services/*/; do
    if [ ! -f "$service_dir/go.mod" ]; then
        continue
    fi
    
    service=$(basename "$service_dir")
    
    if [ -f "$service_dir/cmd/main.go" ]; then
        echo "Building $service..."
        cd "$service_dir"
        go build -o ../../bin/$service ./cmd/main.go
        cd ../..
        echo "  ✓ bin/$service"
    fi
done

echo ""
echo "Built binaries:"
ls -lh bin/ 2>/dev/null || echo "No binaries built"
