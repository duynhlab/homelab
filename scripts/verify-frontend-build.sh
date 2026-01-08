#!/bin/bash
# Frontend Build Verification Script
# Tests frontend build process

set -e

echo "=== Frontend Build Verification ==="
echo ""

# Navigate to frontend directory
cd "$(dirname "$0")/../frontend"

echo "1. Installing dependencies..."
npm ci
echo "Dependencies installed"
echo ""

echo "2. Running lint checks..."
npm run lint
echo "Lint passed"
echo ""

echo "3. Building application..."
npm run build
echo "Build successful"
echo ""

echo "4. Verifying build output..."
if [ ! -f "dist/index.html" ]; then
    echo "ERROR: dist/index.html not found"
    exit 1
fi

if [ ! -d "dist/assets" ]; then
    echo "ERROR: dist/assets directory not found"
    exit 1
fi

echo "Build output:"
ls -lah dist/
echo ""
echo "Build verification complete"
echo ""
echo "=== All frontend checks passed ==="
