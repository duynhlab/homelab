#!/bin/bash
# Validate SLO definitions using Sloth
# This script validates all SLO definition files before generating rules

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFINITIONS_DIR="$PROJECT_ROOT/slo/definitions"

echo "🔍 Validating SLO definitions..."

# Check if Sloth is installed
if ! command -v sloth &> /dev/null; then
    echo "❌ Sloth is not installed!"
    echo ""
    echo "Install Sloth:"
    echo "  # Using Homebrew (macOS):"
    echo "  brew install sloth"
    echo ""
    echo "  # Using Go:"
    echo "  go install github.com/slok/sloth/cmd/sloth@latest"
    echo ""
    echo "  # Using Docker:"
    echo "  docker run --rm -v \$(pwd):/work ghcr.io/slok/sloth:latest validate -i /work/slo/definitions/*.yaml"
    exit 1
fi

# Find definition files (exclude all-services.yaml if it exists)
DEFINITION_FILES=()
while IFS= read -r -d '' file; do
    if [ "$(basename "$file")" != "all-services.yaml" ]; then
        DEFINITION_FILES+=("$file")
    fi
done < <(find "$DEFINITIONS_DIR" -name "*.yaml" -type f -print0)

DEFINITION_COUNT=${#DEFINITION_FILES[@]}

if [ "$DEFINITION_COUNT" -eq 0 ]; then
    echo "❌ No SLO definition files found in $DEFINITIONS_DIR"
    exit 1
fi

echo "📋 Found $DEFINITION_COUNT SLO definition files:"
for file in "${DEFINITION_FILES[@]}"; do
    basename "$file"
done | sort

echo ""
echo "🔍 Validating definitions..."

# Validate each definition file individually
VALIDATION_FAILED=0
for file in "${DEFINITION_FILES[@]}"; do
    echo "  Validating $(basename "$file")..."
    if ! sloth validate -i "$file"; then
        echo "    ❌ $(basename "$file") validation failed!"
        VALIDATION_FAILED=1
    else
        echo "    ✅ $(basename "$file") is valid"
    fi
done

if [ "$VALIDATION_FAILED" -eq 0 ]; then
    echo ""
    echo "✅ All SLO definitions are valid!"
    echo ""
    echo "📊 Summary:"
    echo "   - Total services: $DEFINITION_COUNT"
    echo "   - SLOs per service: 3 (availability, latency, error-rate)"
    echo "   - Total SLOs: $((DEFINITION_COUNT * 3))"
    echo ""
    echo "✅ Ready to generate Prometheus rules!"
    echo ""
    echo "Next step: ./scripts/10-generate-slo-rules.sh"
    exit 0
else
    echo ""
    echo "❌ SLO definition validation failed!"
    echo ""
    echo "Please fix the errors above and try again."
    exit 1
fi

