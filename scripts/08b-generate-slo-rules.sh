#!/bin/bash
# Generate Prometheus SLO rules using Sloth
# This script generates rules from all SLO definition files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFINITIONS_DIR="$PROJECT_ROOT/slo/definitions"
GENERATED_DIR="$PROJECT_ROOT/slo/generated"
OUTPUT_FILE="$GENERATED_DIR/prometheus-rules.yaml"

echo "🔧 Generating Prometheus SLO rules using Sloth..."

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
    echo "  docker run --rm -v \$(pwd):/work ghcr.io/slok/sloth:latest generate -i /work/slo/definitions/*.yaml -o /work/slo/generated/prometheus-rules.yaml"
    exit 1
fi

# Create generated directory
mkdir -p "$GENERATED_DIR"

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

# Validate SLO definitions first
echo ""
echo "📋 Validating SLO definitions..."
VALIDATION_FAILED=0
for file in "${DEFINITION_FILES[@]}"; do
    if ! sloth validate -i "$file"; then
        echo "❌ $(basename "$file") validation failed!"
        VALIDATION_FAILED=1
    fi
done

if [ "$VALIDATION_FAILED" -eq 1 ]; then
    echo "❌ SLO definition validation failed!"
    exit 1
fi

echo "✅ All SLO definitions are valid!"
echo ""

# Generate rules - Sloth supports directory input with exclude pattern
echo "🚀 Generating Prometheus rules..."

# Sloth directory mode requires output to be a directory
# Generate to a temp directory, then merge files
TEMP_OUTPUT_DIR=$(mktemp -d)
trap "rm -rf $TEMP_OUTPUT_DIR" EXIT

# Generate rules using directory mode
sloth generate \
    --input "$DEFINITIONS_DIR" \
    --out "$TEMP_OUTPUT_DIR" \
    --fs-exclude "all-services.yaml"

# Process generated files: keep individual service files AND create merged file
if [ -d "$TEMP_OUTPUT_DIR" ]; then
    # Find all YAML files in output directory
    SERVICE_FILES=$(find "$TEMP_OUTPUT_DIR" -name "*.yaml" -type f | sort)
    
    # Copy individual service files to generated directory (for deployment)
    for rule_file in $SERVICE_FILES; do
        SERVICE_NAME=$(basename "$rule_file" .yaml)
        SERVICE_OUTPUT="$GENERATED_DIR/${SERVICE_NAME}-rules.yaml"
        cp "$rule_file" "$SERVICE_OUTPUT"
        echo "  ✅ Created: $(basename "$SERVICE_OUTPUT")"
    done
    
    # Also create merged file for reference (if small enough)
    FIRST_FILE=$(echo "$SERVICE_FILES" | head -n1)
    if [ -f "$FIRST_FILE" ]; then
        # Copy first file as base
        cp "$FIRST_FILE" "$OUTPUT_FILE"
        
        # Append remaining files (skip first line which is "groups:")
        for rule_file in $(echo "$SERVICE_FILES" | tail -n +2); do
            # Extract groups section and append (skip "groups:" line)
            sed -n '/^- name:/,$p' "$rule_file" >> "$OUTPUT_FILE"
        done
    fi
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Successfully generated Prometheus rules!"
    echo ""
    echo "📄 Output file: $OUTPUT_FILE"
    echo "📊 Rules summary:"
    echo "   - Total lines: $(wc -l < "$OUTPUT_FILE")"
    echo "   - File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
    echo ""
    echo "📋 Next steps:"
    echo "   1. Review generated rules: cat $OUTPUT_FILE"
    echo "   2. Apply to Prometheus: ./scripts/08-deploy-slo.sh"
    echo ""
else
    echo "❌ Failed to generate rules!"
    exit 1
fi

