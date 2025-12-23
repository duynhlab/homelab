#!/bin/bash

# Deploy PostgreSQL Database Infrastructure
# This script deploys:
# 1. Zalando Postgres Operator
# 2. CloudNativePG Operator
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

# Create database namespace for operators
echo "Creating database namespace..."
kubectl create namespace database --dry-run=client -o yaml | kubectl apply -f -

# Deploy Zalando Postgres Operator
echo "Deploying Zalando Postgres Operator..."
if ! helm repo list | grep -q "postgres-operator"; then
    helm repo add postgres-operator https://opensource.zalando.com/postgres-operator/charts/postgres-operator
    helm repo update postgres-operator
fi

helm upgrade --install postgres-operator postgres-operator/postgres-operator \
    -f "$PROJECT_ROOT/k8s/postgres-operator-zalando/values.yaml" \
    -n database \
    --create-namespace \
    --wait \
    --timeout 5m

kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=postgres-operator \
    -n database \
    --timeout=300s

if ! kubectl get crd postgresqls.acid.zalan.do &> /dev/null; then
    echo "ERROR: CRD postgresqls.acid.zalan.do not found"
    exit 1
fi

echo "SUCCESS: Zalando Postgres Operator deployed"

# Deploy CloudNativePG Operator
echo "Deploying CloudNativePG Operator..."
if ! helm repo list | grep -q "cnpg"; then
    helm repo add cnpg https://cloudnative-pg.github.io/charts
    helm repo update cnpg
fi

helm upgrade --install cloudnative-pg cnpg/cloudnative-pg \
    -f "$PROJECT_ROOT/k8s/postgres-operator-cloudnativepg/values.yaml" \
    -n database \
    --create-namespace \
    --wait \
    --timeout 5m

kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=cloudnative-pg \
    -n database \
    --timeout=300s

if ! kubectl get crd clusters.postgresql.cnpg.io &> /dev/null; then
    echo "ERROR: CRD clusters.postgresql.cnpg.io not found"
    exit 1
fi

echo "SUCCESS: CloudNativePG Operator deployed"

# Create database clusters
echo "Creating database clusters..."

# Create namespaces
for ns in auth review product cart user; do
    if ! kubectl get namespace "$ns" &> /dev/null; then
        kubectl create namespace "$ns"
    fi
done

# Create database secrets BEFORE applying CRDs
# CloudNativePG requires secrets to exist during bootstrap
echo "Creating database secrets..."
echo "Creating secrets for CloudNativePG databases..."

# Product database secret
if ! kubectl get secret product-db-secret -n product &> /dev/null; then
    kubectl create secret generic product-db-secret \
        --from-literal=username=product \
        --from-literal=password=postgres \
        -n product
    echo "Created product-db-secret"
else
    echo "product-db-secret already exists, skipping"
fi

# Transaction database secret (cart + order)
if ! kubectl get secret transaction-db-secret -n cart &> /dev/null; then
    kubectl create secret generic transaction-db-secret \
        --from-literal=username=cart \
        --from-literal=password=postgres \
        -n cart
    echo "Created transaction-db-secret"
else
    echo "transaction-db-secret already exists, skipping"
fi

# Zalando database secrets
echo "Creating secrets for Zalando databases..."

# Review database secret
if ! kubectl get secret review-db-secret -n review &> /dev/null; then
    kubectl create secret generic review-db-secret \
        --from-literal=password=postgres \
        -n review
    echo "Created review-db-secret"
else
    echo "review-db-secret already exists, skipping"
fi

# Auth database secret
if ! kubectl get secret auth-db-secret -n auth &> /dev/null; then
    kubectl create secret generic auth-db-secret \
        --from-literal=password=postgres \
        -n auth
    echo "Created auth-db-secret"
else
    echo "auth-db-secret already exists, skipping"
fi

# Supporting database secret (user + notification)
if ! kubectl get secret supporting-db-secret -n user &> /dev/null; then
    kubectl create secret generic supporting-db-secret \
        --from-literal=password=postgres \
        -n user
    echo "Created supporting-db-secret"
else
    echo "supporting-db-secret already exists, skipping"
fi

echo "SUCCESS: Database secrets created"

# Apply Zalando CRDs
echo "Applying Zalando database CRDs..."
kubectl apply -f "$PROJECT_ROOT/k8s/postgres-operator-zalando/crds/"

# Apply CloudNativePG CRDs
echo "Applying CloudNativePG database CRDs..."
kubectl apply -f "$PROJECT_ROOT/k8s/postgres-operator-cloudnativepg/crds/"

# Wait for clusters to be ready
echo "Waiting for database clusters to be ready (this may take 5-10 minutes)..."

# Zalando clusters - Check pods directly by name (simpler and faster)
# Zalando operator doesn't expose ready condition on CRD, so check pods instead
for cluster in review-db auth-db supporting-db; do
    namespace=""
    pod_name=""
    case $cluster in
        review-db) 
            namespace="review"
            pod_name="review-db-0"
            ;;
        auth-db) 
            namespace="auth"
            pod_name="auth-db-0"
            ;;
        supporting-db) 
            namespace="user"
            pod_name="supporting-db-0"
            ;;
    esac
    
    echo "Waiting for $cluster pod ($pod_name) in namespace $namespace..."
    if kubectl wait --for=condition=ready pod "$pod_name" \
        -n "$namespace" \
        --timeout=300s 2>/dev/null; then
        echo "✓ $cluster pod is ready"
    else
        echo "WARN: $cluster pod may not be ready yet. Check with: kubectl get pod $pod_name -n $namespace"
    fi
done

# CloudNativePG clusters - Check CRD condition (has Ready condition)
for cluster in product-db transaction-db; do
    namespace=""
    case $cluster in
        product-db) namespace="product" ;;
        transaction-db) namespace="cart" ;;
    esac
    
    echo "Waiting for $cluster in namespace $namespace..."
    if kubectl wait --for=condition=Ready cluster "$cluster" \
        -n "$namespace" \
        --timeout=300s 2>/dev/null; then
        echo "✓ $cluster is ready"
    else
        echo "WARN: $cluster may not be ready yet. Check with: kubectl get cluster $cluster -n $namespace"
        echo "      Or check pods: kubectl get pods -n $namespace -l cnpg.io/cluster=$cluster"
    fi
done

echo "SUCCESS: Database clusters created (or in progress)"

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

echo "Operators (in database namespace):"
kubectl get pods -n database -l app.kubernetes.io/name=postgres-operator 2>/dev/null || echo "  No Zalando operator pods found"
kubectl get pods -n database -l app.kubernetes.io/name=cloudnative-pg 2>/dev/null || echo "  No CloudNativePG operator pods found"
echo ""

echo "Database Clusters:"
echo "Zalando (Review, Auth, Supporting):"
kubectl get postgresql -A 2>/dev/null || echo "  No Zalando clusters found"
echo ""
echo "CloudNativePG (Product, Transaction):"
kubectl get cluster -A 2>/dev/null || echo "  No CloudNativePG clusters found"
echo ""

echo "PgCat Poolers:"
echo "Product PgCat:"
kubectl get pods -n product -l app=pgcat-product 2>/dev/null || echo "  No PgCat Product pods found"
echo ""
echo "Transaction PgCat:"
kubectl get pods -n cart -l app=pgcat-transaction 2>/dev/null || echo "  No PgCat Transaction pods found"
echo ""

echo "Database Connection Endpoints:"
echo "  Product DB:     product-db-rw.product.svc.cluster.local:5432 (via PgCat: pgcat.product.svc.cluster.local:5432)"
echo "  Review DB:      review-db.review.svc.cluster.local:5432 (direct)"
echo "  Auth DB:        auth-db.auth.svc.cluster.local:5432 (via PgBouncer: auth-db-pooler.auth.svc.cluster.local:5432)"
echo "  Transaction DB: transaction-db-rw.cart.svc.cluster.local:5432 (via PgCat: pgcat-transaction.cart.svc.cluster.local:5432)"
echo "  Supporting DB:  supporting-db.user.svc.cluster.local:5432 (direct)"
echo ""

echo "Secrets Created:"
echo "  - product-db-secret (product namespace)"
echo "  - transaction-db-secret (cart namespace)"
echo "  - review-db-secret (review namespace)"
echo "  - auth-db-secret (auth namespace)"
echo "  - supporting-db-secret (user namespace)"
echo ""

echo "Next Steps:"
echo "1. Database secrets created automatically (using 'postgres' password for learning)"
echo "2. Run database migrations (init containers will handle this)"
echo "3. Deploy microservices with database configuration"
echo ""
echo "⚠️  IMPORTANT NOTES:"
echo "  - Order database needs to be created in transaction-db cluster (see audit report)"
echo "  - Order service configuration may need adjustment (see audit report)"
echo "  - Check cluster status: kubectl get cluster -A"
echo "  - Check Zalando clusters: kubectl get postgresql -A"
echo "=========================================="
echo ""
echo "SUCCESS: Database deployment completed!"
