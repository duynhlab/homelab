#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Deploying All Microservices ===${NC}"

# Deploy namespaces first
echo -e "${GREEN}1. Creating namespaces...${NC}"
kubectl apply -f k8s/namespaces.yaml

# Deploy each service to its namespace
echo -e "${GREEN}2. Deploying auth-service to auth namespace...${NC}"
kubectl apply -f k8s/auth-service/

echo -e "${GREEN}3. Deploying user-service to user namespace...${NC}"
kubectl apply -f k8s/user-service/

echo -e "${GREEN}4. Deploying product-service to product namespace...${NC}"
kubectl apply -f k8s/product-service/

echo -e "${GREEN}5. Deploying cart-service to cart namespace...${NC}"
kubectl apply -f k8s/cart-service/

echo -e "${GREEN}6. Deploying order-service to order namespace...${NC}"
kubectl apply -f k8s/order-service/

echo -e "${GREEN}7. Deploying review-service to review namespace...${NC}"
kubectl apply -f k8s/review-service/

echo -e "${GREEN}8. Deploying notification-service to notification namespace...${NC}"
kubectl apply -f k8s/notification-service/

echo -e "${GREEN}9. Deploying shipping-service to shipping namespace...${NC}"
kubectl apply -f k8s/shipping-service/

echo -e "${GREEN}10. Deploying shipping-service-v2 to shipping namespace...${NC}"
kubectl apply -f k8s/shipping-service-v2/

echo ""
echo -e "${GREEN}🎉 All 9 services deployed!${NC}"

# Wait for pods to be ready
echo -e "${YELLOW}Waiting for pods to be ready...${NC}"
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
echo -e "${GREEN}📊 Pod Status Summary:${NC}"
kubectl get pods -n auth
kubectl get pods -n user
kubectl get pods -n product
kubectl get pods -n cart
kubectl get pods -n order
kubectl get pods -n review
kubectl get pods -n notification
kubectl get pods -n shipping