#!/bin/bash
set -e

SERVICE_NAME=$1

if [ -z "$SERVICE_NAME" ]; then
  echo "ERROR: Service name required"
  exit 1
fi

echo "=== Verifying build for $SERVICE_NAME ==="

# Go module check
echo "1. Running go mod tidy..."
go mod tidy
git diff --exit-code go.mod go.sum || {
  echo "ERROR: go.mod or go.sum changed. Run 'go mod tidy' and commit changes."
  exit 1
}

# Formatting check
echo "2. Checking code formatting..."
UNFORMATTED=$(gofmt -l . | grep -v vendor || true)
if [ -n "$UNFORMATTED" ]; then
  echo "ERROR: Code not formatted. Run 'gofmt -w .'"
  echo "Files needing formatting:"
  echo "$UNFORMATTED"
  exit 1
fi

# Static analysis
echo "3. Running go vet..."
go vet ./...

# Build service
echo "4. Building $SERVICE_NAME..."
go build -o /dev/null ./cmd/$SERVICE_NAME

echo "SUCCESS: All checks passed for $SERVICE_NAME"

