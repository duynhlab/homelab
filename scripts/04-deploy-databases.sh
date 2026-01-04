#!/bin/bash

# Deploy PostgreSQL Database Infrastructure
# This script deploys:
# 1. Zalando Postgres Operator
# 2. CloudNativePG Operator
# 3. All 5 database clusters (with postgres_exporter sidecars for Zalando clusters)
# 4. PgCat connection poolers
# 5. PodMonitors for Prometheus Operator to scrape metrics from sidecars
#
# Usage: ./scripts/04-deploy-databases.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Deploy Zalando Postgres Operator
echo "Deploying Zalando Postgres Operator..."
helm repo add postgres-operator https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo update postgres-operator

helm upgrade --install postgres-operator postgres-operator/postgres-operator \
    -f "$PROJECT_ROOT/k8s/postgres-operator/zalando/values.yaml" \
    -n database \
    --version v1.15.1 \
    --wait \
    --timeout 5m

kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=postgres-operator \
    -n database \
    --timeout=300s

echo "SUCCESS: Zalando Postgres Operator deployed"

# Deploy Postgres Operator UI (optional component)
echo "Deploying Postgres Operator UI..."
helm repo add postgres-operator-ui-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator-ui
helm repo update postgres-operator-ui-charts

helm upgrade --install postgres-operator-ui postgres-operator-ui-charts/postgres-operator-ui \
    -f "$PROJECT_ROOT/k8s/postgres-operator/zalando/ui-values.yaml" \
    -n database \
    --version 1.15.1 \
    --wait \
    --timeout 5m || echo "WARNING: Postgres Operator UI deployment failed (optional component)"

kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=postgres-operator-ui \
    -n database \
    --timeout=300s || echo "WARNING: Postgres Operator UI pod not ready (optional component)"

echo "SUCCESS: Postgres Operator UI deployed (if enabled)"

# Deploy CloudNativePG Operator
echo "Deploying CloudNativePG Operator..."
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update cnpg

helm upgrade --install cloudnative-pg cnpg/cloudnative-pg \
    -f "$PROJECT_ROOT/k8s/postgres-operator/cloudnativepg/values.yaml" \
    -n database \
    --wait \
    --timeout 5m

kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=cloudnative-pg \
    -n database \
    --timeout=300s

echo "SUCCESS: CloudNativePG Operator deployed"

# Create database clusters
echo "Creating database clusters..."

echo "Creating database secrets..."
echo "Applying secrets for CloudNativePG databases from YAML files..."

if [ -f "$PROJECT_ROOT/k8s/secrets/product-db-secret.yaml" ]; then
    kubectl apply -f "$PROJECT_ROOT/k8s/secrets/product-db-secret.yaml"
    echo "Applied product-db-secret from YAML"
else
    echo "WARN: product-db-secret.yaml not found, skipping"
fi

if [ -f "$PROJECT_ROOT/k8s/secrets/transaction-db-secret-cart.yaml" ]; then
    kubectl apply -f "$PROJECT_ROOT/k8s/secrets/transaction-db-secret-cart.yaml"
    echo "Applied transaction-db-secret to cart namespace"
else
    echo "WARN: transaction-db-secret-cart.yaml not found, skipping"
fi

if [ -f "$PROJECT_ROOT/k8s/secrets/transaction-db-secret-order.yaml" ]; then
    kubectl apply -f "$PROJECT_ROOT/k8s/secrets/transaction-db-secret-order.yaml"
    echo "Applied transaction-db-secret to order namespace"
else
    echo "WARN: transaction-db-secret-order.yaml not found, skipping"
fi

echo "SUCCESS: CloudNativePG database secrets created from YAML files"

echo "Applying Zalando database CRDs..."
kubectl apply -f "$PROJECT_ROOT/k8s/postgres-operator/zalando/crds/"

echo "Applying CloudNativePG database CRDs..."
kubectl apply -f "$PROJECT_ROOT/k8s/postgres-operator/cloudnativepg/crds/"

echo "Waiting for database clusters to be ready (this may take 5-10 minutes)..."

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
        echo "SUCCESS: $cluster pod is ready"
    else
        echo "WARN: $cluster pod may not be ready yet. Check with: kubectl get pod $pod_name -n $namespace"
    fi
done

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
        echo "SUCCESS: $cluster is ready"
    else
        echo "WARN: $cluster may not be ready yet. Check with: kubectl get cluster $cluster -n $namespace"
        echo "Or check pods: kubectl get pods -n $namespace -l cnpg.io/cluster=$cluster"
    fi
done

echo "SUCCESS: Database clusters created"

echo "Deploying PgCat connection poolers..."

echo "Deploying PgCat for Product service..."
kubectl apply -f "$PROJECT_ROOT/k8s/postgres-operator/pgcat/product/"

echo "Deploying PgCat for Transaction services..."
kubectl apply -f "$PROJECT_ROOT/k8s/postgres-operator/pgcat/transaction/"

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

# Deploy PodMonitors for postgres_exporter sidecars (all clusters)
echo "Deploying PodMonitors for postgres_exporter sidecars..."
kubectl apply -f "$PROJECT_ROOT/k8s/prometheus/podmonitors/"
echo "SUCCESS: PodMonitors deployed"

# Print summary
echo ""
echo "=========================================="
echo "Database Deployment Summary"
echo "=========================================="
echo ""

echo "Operators in database namespace:"
kubectl get pods -n database -l app.kubernetes.io/name=postgres-operator
kubectl get pods -n database -l app.kubernetes.io/name=cloudnative-pg
echo ""

echo "Database Clusters:"
echo "Zalando (Review, Auth, Supporting):"
kubectl get postgresql -A
echo ""
echo "CloudNativePG (Product, Transaction):"
kubectl get cluster -A
echo ""

echo "PgCat Poolers:"
echo "Product PgCat:"
kubectl get pods -n product -l app=pgcat-product
echo ""
echo "Transaction PgCat:"
kubectl get pods -n cart -l app=pgcat-transaction
echo ""

echo "Database Connection Endpoints:"
echo "  Product DB:     product-db-rw.product.svc.cluster.local:5432 (via PgCat: pgcat.product.svc.cluster.local:5432)"
echo "  Review DB:      review-db.review.svc.cluster.local:5432 (direct)"
echo "  Auth DB:        auth-db.auth.svc.cluster.local:5432 (via PgBouncer: auth-db-pooler.auth.svc.cluster.local:5432)"
echo "  Transaction DB: transaction-db-rw.cart.svc.cluster.local:5432 (via PgCat: pgcat-transaction.cart.svc.cluster.local:5432)"
echo "  Supporting DB:  supporting-db.user.svc.cluster.local:5432 (direct)"
echo ""

echo "Secrets:"
echo "  CloudNativePG (manual, required for bootstrap):"
echo "    - product-db-secret (product namespace)"
echo "    - transaction-db-secret (cart namespace)"
echo "  Zalando (auto-generated by operator):"
echo "    - user.supporting-db.credentials.postgresql.acid.zalan.do (user namespace)"
echo "    - notification.notification.supporting-db.credentials.postgresql.acid.zalan.do (notification namespace, auto-created by operator)"
echo "    - shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do (shipping namespace, auto-created by operator)"
echo "    - review.review-db.credentials.postgresql.acid.zalan.do (review namespace)"
echo "    - auth.auth-db.credentials.postgresql.acid.zalan.do (auth namespace)"
echo ""

echo "Monitoring:"
echo "  - postgres_exporter runs as sidecar in all Zalando PostgreSQL pods"
echo "  - PodMonitors deployed for Prometheus Operator to scrape metrics"
echo "  - Metrics available on port 9187 in each pod"
echo ""
echo "Next Steps:"
echo "1. Zalando operator auto-generates secrets when CRDs are applied"
echo "2. Supporting-db secrets are automatically created in notification and shipping namespaces (via enable_cross_namespace_secret)"
echo "3. Run database migrations (init containers will handle this)"
echo "4. Deploy microservices with database configuration"
echo ""
echo "IMPORTANT NOTES:"
echo "  - Order database is created via postInitSQL in transaction-db CRD"
echo "  - Order service uses cart user (shared user approach)"
echo "  - Supporting-db secrets are automatically created in target namespaces by Zalando operator (enable_cross_namespace_secret: true)"
echo "  - postgres_exporter runs as sidecar in PostgreSQL pods (no separate monitoring user needed)"
echo ""
echo "Verification:"
echo "  Run verification script: ./scripts/04a-verify-databases.sh"
echo "  Or check manually:"
echo "    - Cluster status: kubectl get cluster -A && kubectl get postgresql -A"
echo "    - Order database: kubectl exec -n cart transaction-db-1 -- psql -U cart -d postgres -c \"\\l\" | grep order"
echo "    - PgCat logs: kubectl logs -n cart -l app=pgcat-transaction --tail=50"
echo "    - Sidecar exporters: kubectl get pod -n auth auth-db-0 -o jsonpath='{.spec.containers[*].name}'"
echo "    - Sidecar logs: kubectl logs -n auth auth-db-0 -c exporter"
echo "    - Test metrics: kubectl port-forward -n auth auth-db-0 9187:9187 & curl http://localhost:9187/metrics | grep pg_up"
echo "    - PodMonitors: kubectl get podmonitor -A"
echo "=========================================="
echo ""
echo "SUCCESS: Database deployment completed!"
