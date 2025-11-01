#!/bin/bash
set -e

echo "=== Deploying All Microservices ==="

# Deploy namespaces first
echo "1. Creating namespaces..."
kubectl apply -f k8s/namespaces.yaml

# Deploy each service to its namespace
echo "2. Deploying auth-service to auth namespace..."
kubectl apply -f k8s/auth-service/

echo "3. Deploying user-service to user namespace..."
kubectl apply -f k8s/user-service/

echo "4. Deploying product-service to product namespace..."
kubectl apply -f k8s/product-service/

echo "5. Deploying cart-service to cart namespace..."
kubectl apply -f k8s/cart-service/

echo "6. Deploying order-service to order namespace..."
kubectl apply -f k8s/order-service/

echo "7. Deploying review-service to review namespace..."
kubectl apply -f k8s/review-service/

echo "8. Deploying notification-service to notification namespace..."
kubectl apply -f k8s/notification-service/

echo "9. Deploying shipping-service to shipping namespace..."
kubectl apply -f k8s/shipping-service/

echo "10. Deploying shipping-service-v2 to shipping namespace..."
kubectl apply -f k8s/shipping-service-v2/

echo ""
echo "🎉 All 9 services deployed!"

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=auth-service -n auth --timeout=60s || true
kubectl wait --for=condition=ready pod -l app=user-service -n user --timeout=60s || true
kubectl wait --for=condition=ready pod -l app=product-service -n product --timeout=60s || true
kubectl wait --for=condition=ready pod -l app=cart-service -n cart --timeout=60s || true
kubectl wait --for=condition=ready pod -l app=order-service -n order --timeout=60s || true
kubectl wait --for=condition=ready pod -l app=review-service -n review --timeout=60s || true
kubectl wait --for=condition=ready pod -l app=notification-service -n notification --timeout=60s || true
kubectl wait --for=condition=ready pod -l app=shipping-service -n shipping --timeout=60s || true
kubectl wait --for=condition=ready pod -l app=shipping-service-v2 -n shipping --timeout=60s || true

echo ""
echo "📊 Pod Status Summary:"
kubectl get pods -n auth
kubectl get pods -n user
kubectl get pods -n product
kubectl get pods -n cart
kubectl get pods -n order
kubectl get pods -n review
kubectl get pods -n notification
kubectl get pods -n shipping