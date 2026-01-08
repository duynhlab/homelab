#!/bin/bash
# Docker Build and Test Script for Frontend
# Usage: ./scripts/test-frontend-docker.sh

set -e

echo "=== Frontend Docker Build Test ==="
echo ""

cd "$(dirname "$0")/.."

IMAGE_NAME="frontend-test:latest"
API_URL="http://localhost:8080"

echo "1. Building Docker image with API_BASE_URL..."
docker build \
  --build-arg API_BASE_URL="${API_URL}" \
  -t "${IMAGE_NAME}" \
  -f frontend/Dockerfile \
  frontend/

echo "✅ Docker build successful"
echo ""

echo "2. Checking image size..."
SIZE=$(docker images "${IMAGE_NAME}" --format "{{.Size}}")
echo "Image size: ${SIZE}"
echo ""

echo "3. Starting container (no runtime env needed)..."
CONTAINER_ID=$(docker run -d -p 3000:80 "${IMAGE_NAME}")

echo "Container ID: ${CONTAINER_ID}"
sleep 3

echo ""
echo "4. Testing health endpoint..."
if curl -f http://localhost:3000/health; then
    echo ""
    echo "✅ Health check passed"
else
    echo ""
    echo "❌ Health check failed"
    docker logs "${CONTAINER_ID}"
    docker stop "${CONTAINER_ID}"
    exit 1
fi

echo ""
echo "5. Testing index.html..."
if curl -f http://localhost:3000/ | grep -q "<!doctype html>"; then
    echo "✅ Index page served successfully"
else
    echo "❌ Index page failed"
    docker stop "${CONTAINER_ID}"
    exit 1
fi

echo ""
echo "Stopping container..."
docker stop "${CONTAINER_ID}"
docker rm "${CONTAINER_ID}"

echo ""
echo "=== Frontend Docker test passed ==="
echo ""
echo "API URL was baked into build: ${API_URL}"
echo ""
echo "To run manually:"
echo "  docker run -d -p 3000:80 ${IMAGE_NAME}"
