#!/bin/bash
set -e

# Configuration
SERVICES=("auth" "user" "product" "cart" "order" "review" "notification" "shipping")
BASE_TARGET_DIR="/home/duydo/Working/duynhne"
TEMPLATE_FILE="/home/duydo/Working/duy/Github/monitoring/docs/platform/ci_template.yml"

# Verify Template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "Error: Template file not found at $TEMPLATE_FILE"
  exit 1
fi

for SERVICE in "${SERVICES[@]}"; do
  FULL_SERVICE_NAME="${SERVICE}-service"
  SHORT_SERVICE_NAME="${SERVICE}"
  TARGET_Repo="$BASE_TARGET_DIR/$FULL_SERVICE_NAME"
  TARGET_FILE="$TARGET_Repo/.github/workflows/ci.yml"

  echo "--------------------------------------------------"
  echo "Processing $FULL_SERVICE_NAME..."

  if [ ! -d "$TARGET_Repo" ]; then
    echo "⚠️  Warning: Repository directory $TARGET_Repo not found. Skipping."
    continue
  fi

  # Apply Template with substitution
  sed -e "s/{{SERVICE_NAME}}/$FULL_SERVICE_NAME/g" \
      -e "s/{{SERVICE_SHORT}}/$SHORT_SERVICE_NAME/g" \
      "$TEMPLATE_FILE" > "$TARGET_FILE"

  echo "✅ Updated ci.yml for $FULL_SERVICE_NAME"

  # Git Operations
  cd "$TARGET_Repo"
  
  if git diff --quiet && git diff --cached --quiet; then
      echo "No changes to commit for $FULL_SERVICE_NAME."
  else
      git add .github/workflows/ci.yml
      git commit -m "fix(ci): add top-level permissions for GHCR push"
      git push
      echo "🚀 Pushed changes to $FULL_SERVICE_NAME"
  fi
done

echo "--------------------------------------------------"
echo "🎉 rollout complete!"
