#!/bin/bash
# Run tests for all Go services
set -e

export PATH=$PATH:/usr/local/go/bin
echo "=== Testing all services ==="

for service_dir in services/*/; do
    if [ ! -f "$service_dir/go.mod" ]; then
        continue
    fi
    
    service=$(basename "$service_dir")
    echo "Testing $service..."
    cd "$service_dir"
    go test -v ./...
    cd ../..
done

echo ""
echo "All tests passed!"
