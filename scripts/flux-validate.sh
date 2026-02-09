#!/usr/bin/env bash
set -e



echo "Validating Flux Kustomizations..."

validate_kustomize() {
    local path=$1
    local name=$2
    echo -n "   - Checking $name ($path)... "
    if kubectl kustomize "$path" --load-restrictor LoadRestrictionsNone > /dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
        echo "   !!! Error output:"
        kubectl kustomize "$path" --load-restrictor LoadRestrictionsNone > /dev/null
        exit 1
    fi
}

validate_yaml() {
    local path=$1
    local name=$2
    echo -n "   - Checking $name ($path)... "
    if kubectl apply --dry-run=client -f "$path" > /dev/null 2>&1; then
        echo "OK"
    else
        echo "FAILED"
        echo "   !!! Error output:"
        kubectl apply --dry-run=client -f "$path"
        exit 1
    fi
}

# 1. Cluster Configs
echo "1. Cluster Configurations:"
validate_kustomize "kubernetes/clusters/local" "Local Cluster"

# 2. Infrastructure Kustomizations (matches Flux Kustomization paths)
echo "2. Infrastructure:"
validate_kustomize "kubernetes/infra/controllers" "Controllers"
validate_kustomize "kubernetes/infra/configs/databases" "Databases"
validate_kustomize "kubernetes/infra/configs/monitoring" "Monitoring"
validate_kustomize "kubernetes/infra/configs/secrets" "Secrets"

# 3. Apps (Iterate individual files as there is no kustomization.yaml yet)
echo "3. Applications:"
for f in kubernetes/apps/*.yaml; do
    filename=$(basename "$f")
    validate_yaml "$f" "$filename"
done

# 4. Production Cluster (if exists)
if [ -d "kubernetes/clusters/production" ]; then
    echo "4. Production Cluster:"
    validate_kustomize "kubernetes/clusters/production" "Production Cluster"
fi

echo -e "\n All configurations are valid!"
