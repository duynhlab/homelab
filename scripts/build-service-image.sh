#!/bin/bash
# Build Docker image for a specific service
# Usage: ./build-service-image.sh <service-name>

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <service-name>"
    echo "Example: $0 cart"
    echo ""
    echo "Available services:"
    ls -d services/*/ | xargs -n 1 basename
    exit 1
fi

SERVICE_NAME=$1
SERVICE_DIR="services/$SERVICE_NAME"

if [ ! -d "$SERVICE_DIR" ]; then
    echo "Error: Service directory $SERVICE_DIR not found"
    exit 1
fi

if [ ! -f "$SERVICE_DIR/go.mod" ]; then
    echo "Error: $SERVICE_DIR/go.mod not found"
    exit 1
fi

echo "=== Building Docker image for $SERVICE_NAME service ==="

# Build from services directory
cd services

# Build the image
docker build \
    --build-arg SERVICE_NAME=$SERVICE_NAME \
    -t monitoring-${SERVICE_NAME}:latest \
    -f Dockerfile \
    .

echo ""
echo "Docker image built successfully: monitoring-${SERVICE_NAME}:latest"
echo ""
echo "To run the service:"
echo "  docker run -p 8080:8080 monitoring-${SERVICE_NAME}:latest"
