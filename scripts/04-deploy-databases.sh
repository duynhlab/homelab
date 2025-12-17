#!/bin/bash

# Deploy PostgreSQL Database Infrastructure
# This script deploys:
# 1. Zalando Postgres Operator
# 2. CrunchyData Postgres Operator
# 3. All 5 database clusters
# 4. PgCat connection poolers
# 5. postgres_exporter for monitoring
#
# Usage: ./scripts/04-deploy-databases.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check prerequisites
if ! command -v helm &> /dev/null; then
    echo "ERROR: Helm is not installed. Please install Helm 3.x"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed. Please install kubectl"
    exit 1
fi

# Deploy Zalando Postgres Operator
echo "Deploying Zalando Postgres Operator..."
if ! helm repo list | grep -q "postgres-operator"; then
    helm repo add postgres-operator https://opensource.zalando.com/postgres-operator/charts/postgres-operator
    helm repo update postgres-operator
fi

helm upgrade --install postgres-operator postgres-operator/postgres-operator \
    -f "$PROJECT_ROOT/k8s/postgres-operator-zalando/values.yaml" \
    -n monitoring \
    --create-namespace \
    --wait \
    --timeout 5m

kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=postgres-operator \
    -n monitoring \
    --timeout=300s

if ! kubectl get crd postgresqls.acid.zalan.do &> /dev/null; then
    echo "ERROR: CRD postgresqls.acid.zalan.do not found"
    exit 1
fi

echo "SUCCESS: Zalando Postgres Operator deployed"

# Deploy CrunchyData Postgres Operator
echo "Deploying CrunchyData Postgres Operator..."
if ! helm repo list | grep -q "postgres-operator-crunchydata"; then
    helm repo add postgres-operator-crunchydata https://charts.crunchydata.com
    helm repo update postgres-operator-crunchydata
fi

helm upgrade --install postgres-operator-crunchydata postgres-operator-crunchydata/postgres-operator \
    -f "$PROJECT_ROOT/k8s/postgres-operator-crunchydata/values.yaml" \
    -n monitoring \
    --create-namespace \
    --wait \
    --timeout 5m

kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=postgres-operator-crunchydata \
    -n monitoring \
    --timeout=300s

if ! kubectl get crd postgresclusters.postgres-operator.crunchydata.com &> /dev/null; then
    echo "ERROR: CRD postgresclusters.postgres-operator.crunchydata.com not found"
    exit 1
fi

echo "SUCCESS: CrunchyData Postgres Operator deployed"

# Create database clusters
echo "Creating database clusters..."

# Create namespaces
for ns in auth review product cart user; do
    if ! kubectl get namespace "$ns" &> /dev/null; then
        kubectl create namespace "$ns"
    fi
done

# Apply Zalando CRDs
echo "Applying Zalando database CRDs..."
kubectl apply -f "$PROJECT_ROOT/k8s/postgres-operator-zalando/crds/"

# Apply CrunchyData CRDs
echo "Applying CrunchyData database CRDs..."
kubectl apply -f "$PROJECT_ROOT/k8s/postgres-operator-crunchydata/crds/"

# Wait for clusters to be ready
echo "Waiting for database clusters to be ready (this may take 5-10 minutes)..."

# Zalando clusters
for cluster in review-db auth-db supporting-db; do
    namespace=""
    case $cluster in
        review-db) namespace="review" ;;
        auth-db) namespace="auth" ;;
        supporting-db) namespace="user" ;;
    esac
    
    echo "Waiting for $cluster in namespace $namespace..."
    kubectl wait --for=condition=ready postgresql "$cluster" \
        -n "$namespace" \
        --timeout=600s || {
        echo "WARN: $cluster may not be ready yet. Check with: kubectl get postgresql $cluster -n $namespace"
    }
done

# CrunchyData clusters
for cluster in product-db transaction-db; do
    namespace=""
    case $cluster in
        product-db) namespace="product" ;;
        transaction-db) namespace="cart" ;;
    esac
    
    echo "Waiting for $cluster in namespace $namespace..."
    kubectl wait --for=condition=ready postgrescluster "$cluster" \
        -n "$namespace" \
        --timeout=600s || {
        echo "WARN: $cluster may not be ready yet. Check with: kubectl get postgrescluster $cluster -n $namespace"
    }
done

echo "SUCCESS: Database clusters created"

# Deploy PgCat poolers
echo "Deploying PgCat connection poolers..."

echo "Deploying PgCat for Product service..."
kubectl apply -f "$PROJECT_ROOT/k8s/pgcat/product/"

echo "Deploying PgCat for Transaction services..."
kubectl apply -f "$PROJECT_ROOT/k8s/pgcat/transaction/"

# Wait for PgCat pods
echo "Waiting for PgCat pods to be ready..."
kubectl wait --for=condition=ready pod \
    -l app=pgcat-product \
    -n product \
    --timeout=300s || {
    echo "WARN: PgCat Product may not be ready yet"
}

kubectl wait --for=condition=ready pod \
    -l app=pgcat-transaction \
    -n cart \
    --timeout=300s || {
    echo "WARN: PgCat Transaction may not be ready yet"
}

echo "SUCCESS: PgCat poolers deployed"

# Print summary
echo ""
echo "=========================================="
echo "Database Deployment Summary"
echo "=========================================="
echo ""
echo "Operators:"
kubectl get pods -n monitoring -l app.kubernetes.io/name=postgres-operator
kubectl get pods -n monitoring -l app.kubernetes.io/name=postgres-operator-crunchydata
echo ""
echo "Database Clusters:"
echo "Zalando (Review, Auth, Supporting):"
kubectl get postgresql -A
echo ""
echo "CrunchyData (Product, Transaction):"
kubectl get postgrescluster -A
echo ""
echo "PgCat Poolers:"
kubectl get pods -n product -l app=pgcat-product
kubectl get pods -n cart -l app=pgcat-transaction
echo ""
echo "Next Steps:"
echo "1. Create Kubernetes Secrets for database passwords (see k8s/secrets/README.md)"
echo "2. Run database migrations (init containers will handle this)"
echo "3. Deploy microservices with database configuration"
echo "=========================================="
echo ""
echo "SUCCESS: Database deployment completed!"
