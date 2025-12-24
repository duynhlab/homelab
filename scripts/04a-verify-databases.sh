#!/bin/bash

# Verify Database Readiness and Connection Testing
# This script checks:
# 1. Database cluster status (Ready condition)
# 2. Database pods are running
# 3. Databases exist and are accessible
# 4. Connection testing
# 5. PgCat poolers can connect
#
# Usage: ./scripts/04a-verify-databases.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed"
    exit 1
fi

echo "=========================================="
echo "Database Readiness Verification"
echo "=========================================="
echo ""

# Function to check cluster status
check_cluster_status() {
    local cluster=$1
    local namespace=$2
    local operator=$3
    
    echo "INFO: Checking $cluster ($operator) in namespace $namespace..."
    
    if [ "$operator" == "zalando" ]; then
        # Zalando: Check pod status
        local pod_name="${cluster}-0"
        if kubectl get pod "$pod_name" -n "$namespace" &> /dev/null; then
            local status=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}')
            if [ "$status" == "Running" ]; then
                local ready=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.containerStatuses[0].ready}')
                if [ "$ready" == "true" ]; then
                    echo "  SUCCESS: Pod is Ready"
                    return 0
                else
                    echo "  WARN: Pod Running but not Ready"
                    return 1
                fi
            else
                echo "  ERROR: Pod status: $status"
                return 1
            fi
        else
            echo "  ERROR: Pod not found"
            return 1
        fi
    else
        # CloudNativePG: Check cluster Ready condition
        if kubectl get cluster "$cluster" -n "$namespace" &> /dev/null; then
            local ready=$(kubectl get cluster "$cluster" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            if [ "$ready" == "True" ]; then
                echo "  SUCCESS: Cluster is Ready"
                return 0
            else
                echo "  WARN: Cluster exists but not Ready"
                return 1
            fi
        else
            echo "  ERROR: Cluster not found"
            return 1
        fi
    fi
}

# Function to list databases in cluster
list_databases() {
    local cluster=$1
    local namespace=$2
    local operator=$3
    
    if [ "$operator" == "zalando" ]; then
        local pod_name="${cluster}-0"
        if kubectl get pod "$pod_name" -n "$namespace" &> /dev/null; then
            kubectl exec -n "$namespace" "$pod_name" -- psql -U postgres -d postgres -c "\l" 2>/dev/null | sed 's/^/    /'
            return 0
        fi
    else
        local primary_pod=$(kubectl get pods -n "$namespace" -l cnpg.io/cluster="$cluster",role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -z "$primary_pod" ]; then
            primary_pod=$(kubectl get pods -n "$namespace" -l cnpg.io/cluster="$cluster" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        fi
        if [ -n "$primary_pod" ]; then
            kubectl exec -n "$namespace" "$primary_pod" -- psql -U postgres -d postgres -c "\l" 2>/dev/null | sed 's/^/    /'
            return 0
        fi
    fi
    return 1
}

# Function to check database exists and test connection
check_database() {
    local cluster=$1
    local namespace=$2
    local database=$3
    local user=$4
    local operator=$5
    
    if [ "$operator" == "zalando" ]; then
        local pod_name="${cluster}-0"
        if kubectl exec -n "$namespace" "$pod_name" -- psql -U "$user" -d "$database" -c "SELECT 1;" &> /dev/null; then
            echo "    SUCCESS: Database '$database' exists and accessible"
            return 0
        else
            echo "    ERROR: Database '$database' not found or not accessible"
            return 1
        fi
    else
        local primary_pod=$(kubectl get pods -n "$namespace" -l cnpg.io/cluster="$cluster",role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -z "$primary_pod" ]; then
            primary_pod=$(kubectl get pods -n "$namespace" -l cnpg.io/cluster="$cluster" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        fi
        if [ -n "$primary_pod" ]; then
            # Try connection with password first, fallback to postgres user
            local secret_name="${cluster}-secret"
            if [ "$cluster" == "product-db" ]; then
                secret_name="product-db-secret"
            elif [ "$cluster" == "transaction-db" ]; then
                secret_name="transaction-db-secret"
            fi
            local password=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
            
            if [ -n "$password" ]; then
                if kubectl exec -n "$namespace" "$primary_pod" -- env PGPASSWORD="$password" psql -h localhost -U "$user" -d "$database" -c "SELECT 1;" &> /dev/null; then
                    echo "    SUCCESS: Database '$database' exists and accessible"
                    return 0
                fi
            fi
            # Fallback to postgres user
            if kubectl exec -n "$namespace" "$primary_pod" -- psql -U postgres -d "$database" -c "SELECT 1;" &> /dev/null; then
                echo "    SUCCESS: Database '$database' exists and accessible"
                return 0
            fi
        fi
        echo "    ERROR: Database '$database' not found or not accessible"
        return 1
    fi
}


# Function to check PgCat pooler
check_pgcat_pooler() {
    local pooler=$1
    local namespace=$2
    local pool_name=$3
    local database=$4  # Database name (usually same as pool_name)
    
    # Use pool_name as database if not provided
    if [ -z "$database" ]; then
        database="$pool_name"
    fi
    
    local pgcat_pod=$(kubectl get pods -n "$namespace" -l app="$pooler" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -z "$pgcat_pod" ]; then
        echo "    WARN: PgCat pod not found"
        return 1
    fi
    
    local ready=$(kubectl get pod "$pgcat_pod" -n "$namespace" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    if [ "$ready" != "true" ]; then
        echo "    WARN: PgCat pod not ready"
        return 1
    fi
    
    # Determine database host based on namespace (CloudNativePG pattern)
    local db_host=""
    if [ "$namespace" == "cart" ]; then
        db_host="transaction-db-rw.cart.svc.cluster.local"
    elif [ "$namespace" == "product" ]; then
        db_host="product-db-rw.product.svc.cluster.local"
    else
        echo "    WARN: Unknown namespace for database host"
        return 1
    fi
    
    # Test connection from PgCat pod to database (verify PgCat can connect)
    local test_result=$(kubectl exec -n "$namespace" "$pgcat_pod" -- bash -c "PGPASSWORD=postgres psql -h $db_host -U $pool_name -d $database -c 'SELECT current_database();' 2>&1" || echo "")
    
    if echo "$test_result" | grep -q "$database"; then
        echo "    SUCCESS: PgCat connection verified (database: $database)"
        return 0
    else
        echo "    WARN: PgCat connection test failed (check: kubectl logs -n $namespace $pgcat_pod)"
        return 1
    fi
}

# Check Zalando clusters
echo "=== Zalando Postgres Operator Clusters ==="
echo ""

# Review database
echo "1. Review Database:"
if check_cluster_status "review-db" "review" "zalando"; then
    list_databases "review-db" "review" "zalando"
    check_database "review-db" "review" "review" "review" "zalando"
fi
echo ""

# Auth database
echo "2. Auth Database:"
if check_cluster_status "auth-db" "auth" "zalando"; then
    list_databases "auth-db" "auth" "zalando"
    check_database "auth-db" "auth" "auth" "auth" "zalando"
    pooler_pod=$(kubectl get pods -n auth -l application=db-connection-pooler,cluster-name=auth-db -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$pooler_pod" ]; then
        echo "    SUCCESS: PgBouncer available"
    else
        echo "    WARN: PgBouncer not found"
    fi
fi
echo ""

# Supporting database
echo "3. Supporting Database (User + Notification + Shipping-v2):"
if check_cluster_status "supporting-db" "user" "zalando"; then
    list_databases "supporting-db" "user" "zalando"
    check_database "supporting-db" "user" "user" "user" "zalando"
    check_database "supporting-db" "user" "notification" "notification" "zalando"
    check_database "supporting-db" "user" "shipping" "shipping" "zalando"
fi
echo ""

# Check CloudNativePG clusters
echo "=== CloudNativePG Operator Clusters ==="
echo ""

# Product database
echo "4. Product Database:"
if check_cluster_status "product-db" "product" "cloudnativepg"; then
    list_databases "product-db" "product" "cloudnativepg"
    check_database "product-db" "product" "product" "product" "cloudnativepg"
    check_pgcat_pooler "pgcat-product" "product" "product" "product"
fi
echo ""

# Transaction database (Cart + Order)
echo "5. Transaction Database (Cart + Order):"
if check_cluster_status "transaction-db" "cart" "cloudnativepg"; then
    list_databases "transaction-db" "cart" "cloudnativepg"
    check_database "transaction-db" "cart" "cart" "cart" "cloudnativepg"
    if ! check_database "transaction-db" "cart" "order" "cart" "cloudnativepg"; then
        echo "    WARN: Order database missing - recreate cluster: kubectl delete cluster transaction-db -n cart && kubectl apply -f k8s/postgres-operator-cloudnativepg/crds/transaction-db.yaml"
    fi
    check_pgcat_pooler "pgcat-transaction" "cart" "cart" "cart"
    check_pgcat_pooler "pgcat-transaction" "cart" "cart" "order"
fi
echo ""

echo "=========================================="
echo "Verification Complete"
echo "=========================================="
