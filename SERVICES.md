# 📦 Services & Repositories

This project follows a **Polyrepo** architecture. The `monitoring` repository acts as the central **Infrastructure & GitOps** hub, while application code resides in independent repositories.

## 🏭 Infrastructure & Core

| Component | Repository | Description | Status |
|-----------|------------|-------------|--------|
| **Infrastructure** | [duynhne/monitoring](https://github.com/duynhne/monitoring) | GitOps, Helm Charts, K8s Manifests, Docs | [![CI](https://github.com/duynhne/monitoring/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhne/monitoring/actions) |
| **Shared Workflows** | [duyhenryer/shared-workflows](https://github.com/duyhenryer/shared-workflows) | Reusable GitHub Actions (CI/CD) | [![CI](https://github.com/duyhenryer/shared-workflows/actions/workflows/ci.yml/badge.svg)](https://github.com/duyhenryer/shared-workflows/actions) |
| **Common Lib** | [duynhne/pkg](https://github.com/duynhne/pkg) | Shared Go Maven/Library | [![CI](https://github.com/duynhne/pkg/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhne/pkg/actions) |

## 🚀 Microservices

All microservices are hosted in the `duynhne` organization.

| Service | Repository | Port | CI Status | Docker Image |
|---------|------------|------|-----------|--------------|
| **Auth** | [duynhne/auth-service](https://github.com/duynhne/auth-service) | 8001 | [![CI](https://github.com/duynhne/auth-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhne/auth-service/actions) | `ghcr.io/duynhne/auth-service` |
| **User** | [duynhne/user-service](https://github.com/duynhne/user-service) | 8002 | [![CI](https://github.com/duynhne/user-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhne/user-service/actions) | `ghcr.io/duynhne/user-service` |
| **Product** | [duynhne/product-service](https://github.com/duynhne/product-service) | 8003 | [![CI](https://github.com/duynhne/product-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhne/product-service/actions) | `ghcr.io/duynhne/product-service` |
| **Cart** | [duynhne/cart-service](https://github.com/duynhne/cart-service) | 8004 | [![CI](https://github.com/duynhne/cart-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhne/cart-service/actions) | `ghcr.io/duynhne/cart-service` |
| **Order** | [duynhne/order-service](https://github.com/duynhne/order-service) | 8005 | [![CI](https://github.com/duynhne/order-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhne/order-service/actions) | `ghcr.io/duynhne/order-service` |
| **Review** | [duynhne/review-service](https://github.com/duynhne/review-service) | 8006 | [![CI](https://github.com/duynhne/review-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhne/review-service/actions) | `ghcr.io/duynhne/review-service` |
| **Notification** | [duynhne/notification-service](https://github.com/duynhne/notification-service) | 8007 | [![CI](https://github.com/duynhne/notification-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhne/notification-service/actions) | `ghcr.io/duynhne/notification-service` |
| **Shipping** | [duynhne/shipping-service](https://github.com/duynhne/shipping-service) | 8008 | [![CI](https://github.com/duynhne/shipping-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhne/shipping-service/actions) | `ghcr.io/duynhne/shipping-service` |

## 💻 Frontend

| Component | Repository | Port | CI Status | Docker Image |
|-----------|------------|------|-----------|--------------|
| **Frontend** | [duynhne/frontend](https://github.com/duynhne/frontend) | 3000 | [![CI](https://github.com/duynhne/frontend/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhne/frontend/actions) | `ghcr.io/duynhne/frontend` |

## 🛠️ Setup

To clone all repositories for local development, follow the instructions in [docs/platform/SETUP.md](docs/platform/SETUP.md).
