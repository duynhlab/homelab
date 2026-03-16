# 📦 Services & Repositories

This project follows a **Polyrepo** architecture. The `monitoring` repository acts as the central **Infrastructure & GitOps** hub, while application code resides in independent repositories.

## 🏭 Infrastructure & Core

| Component | Repository | Description | Status |
|-----------|------------|-------------|--------|
| **Infrastructure** | [duynhlab/monitoring](https://github.com/duynhlab/monitoring) | GitOps, Helm Charts, K8s Manifests, Docs | [![CI](https://github.com/duynhlab/monitoring/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/monitoring/actions) |
| **Shared Workflows** | [duyhenryer/shared-workflows](https://github.com/duyhenryer/shared-workflows) | Reusable GitHub Actions (CI/CD) | [![CI](https://github.com/duyhenryer/shared-workflows/actions/workflows/ci.yml/badge.svg)](https://github.com/duyhenryer/shared-workflows/actions) |
| **Common Lib** | [duynhlab/pkg](https://github.com/duynhlab/pkg) | Shared Go Maven/Library | [![CI](https://github.com/duynhlab/pkg/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/pkg/actions) |

## 🚀 Microservices

All microservices are hosted in the `duynhlab` organization.

| Service | Repository | Port | CI Status | Docker Image |
|---------|------------|------|-----------|--------------|
| **Auth** | [duynhlab/auth-service](https://github.com/duynhlab/auth-service) | 8001 | [![CI](https://github.com/duynhlab/auth-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/auth-service/actions) | `ghcr.io/duynhlab/auth-service/auth` |
| **User** | [duynhlab/user-service](https://github.com/duynhlab/user-service) | 8002 | [![CI](https://github.com/duynhlab/user-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/user-service/actions) | `ghcr.io/duynhlab/user-service/user` |
| **Product** | [duynhlab/product-service](https://github.com/duynhlab/product-service) | 8003 | [![CI](https://github.com/duynhlab/product-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/product-service/actions) | `ghcr.io/duynhlab/product-service/product` |
| **Cart** | [duynhlab/cart-service](https://github.com/duynhlab/cart-service) | 8004 | [![CI](https://github.com/duynhlab/cart-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/cart-service/actions) | `ghcr.io/duynhlab/cart-service/cart` |
| **Order** | [duynhlab/order-service](https://github.com/duynhlab/order-service) | 8005 | [![CI](https://github.com/duynhlab/order-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/order-service/actions) | `ghcr.io/duynhlab/order-service/order` |
| **Review** | [duynhlab/review-service](https://github.com/duynhlab/review-service) | 8006 | [![CI](https://github.com/duynhlab/review-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/review-service/actions) | `ghcr.io/duynhlab/review-service/review` |
| **Notification** | [duynhlab/notification-service](https://github.com/duynhlab/notification-service) | 8007 | [![CI](https://github.com/duynhlab/notification-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/notification-service/actions) | `ghcr.io/duynhlab/notification-service/notification` |
| **Shipping** | [duynhlab/shipping-service](https://github.com/duynhlab/shipping-service) | 8008 | [![CI](https://github.com/duynhlab/shipping-service/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/shipping-service/actions) | `ghcr.io/duynhlab/shipping-service/shipping` |

## 💻 Frontend

| Component | Repository | Port | CI Status | Docker Image |
|-----------|------------|------|-----------|--------------|
| **Frontend** | [duynhlab/frontend](https://github.com/duynhlab/frontend) | 3000 | [![CI](https://github.com/duynhlab/frontend/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/frontend/actions) | `ghcr.io/duynhlab/frontend/frontend` |

## 🛠️ Setup

To clone all repositories for local development, follow the instructions in [docs/platform/SETUP.md](docs/platform/SETUP.md).
