# 📦 Services & Repositories

This project follows a **Polyrepo** architecture. The `homelab` repository acts as the central **Infrastructure & GitOps** hub, while application code resides in independent repositories.

## 🏭 Infrastructure & Core

| Component | Repository | Description | Status |
|-----------|------------|-------------|--------|
| **Infrastructure** | [duynhlab/homelab](https://github.com/duynhlab/homelab) | GitOps, K8s Manifests, Docs | [![CI](https://github.com/duynhlab/homelab/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/homelab/actions) |
| **Helm Charts** | [duynhlab/helm-charts](https://github.com/duynhlab/helm-charts) | `mop` microservice chart (Deployment, HTTP + headless gRPC Services, migrations, SLO) — OCI `ghcr.io/duynhlab/helm-charts/mop` | [![CI](https://github.com/duynhlab/helm-charts/actions/workflows/e2e.yml/badge.svg)](https://github.com/duynhlab/helm-charts/actions) |
| **Shared Workflows** | [duynhlab/gha-workflows](https://github.com/duynhlab/gha-workflows) | Reusable GitHub Actions (CI/CD) | [![CI](https://github.com/duynhlab/gha-workflows/actions/workflows/pr-checks.yml/badge.svg)](https://github.com/duynhlab/gha-workflows/actions) |
| **Common Lib** | [duynhlab/pkg](https://github.com/duynhlab/pkg) | Shared Go Maven/Library | [![CI](https://github.com/duynhlab/pkg/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/pkg/actions) |

## 🚀 Microservices

All microservices are hosted in the `duynhlab` organization.

| Service | Repository | Port | CI Status | Docker Image |
|---------|------------|------|-----------|--------------|
| **Auth** | [duynhlab/auth-service](https://github.com/duynhlab/auth-service) | 8001 | [![CI](https://github.com/duynhlab/auth-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/auth-service/actions) | `ghcr.io/duynhlab/auth-service/auth-service` |
| **User** | [duynhlab/user-service](https://github.com/duynhlab/user-service) | 8002 | [![CI](https://github.com/duynhlab/user-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/user-service/actions) | `ghcr.io/duynhlab/user-service/user-service` |
| **Product** | [duynhlab/product-service](https://github.com/duynhlab/product-service) | 8003 | [![CI](https://github.com/duynhlab/product-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/product-service/actions) | `ghcr.io/duynhlab/product-service/product-service` |
| **Cart** | [duynhlab/cart-service](https://github.com/duynhlab/cart-service) | 8004 | [![CI](https://github.com/duynhlab/cart-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/cart-service/actions) | `ghcr.io/duynhlab/cart-service/cart-service` |
| **Order** | [duynhlab/order-service](https://github.com/duynhlab/order-service) | 8005 | [![CI](https://github.com/duynhlab/order-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/order-service/actions) | `ghcr.io/duynhlab/order-service/order-service` |
| **Review** | [duynhlab/review-service](https://github.com/duynhlab/review-service) | 8006 | [![CI](https://github.com/duynhlab/review-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/review-service/actions) | `ghcr.io/duynhlab/review-service/review-service` |
| **Notification** | [duynhlab/notification-service](https://github.com/duynhlab/notification-service) | 8007 | [![CI](https://github.com/duynhlab/notification-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/notification-service/actions) | `ghcr.io/duynhlab/notification-service/notification-service` |
| **Shipping** | [duynhlab/shipping-service](https://github.com/duynhlab/shipping-service) | 8008 | [![CI](https://github.com/duynhlab/shipping-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/shipping-service/actions) | `ghcr.io/duynhlab/shipping-service/shipping-service` |
| **Payment** | [duynhlab/payment-service](https://github.com/duynhlab/payment-service) | 8009 | [![CI](https://github.com/duynhlab/payment-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/payment-service/actions) | `ghcr.io/duynhlab/payment-service/payment-service` |

> **Payment** is built and runs in local-stack (checkout domain); cluster GitOps
> deployment is [RFC-0010](docs/proposals/rfc/RFC-0010/) P5.

## 💻 Frontend

| Component | Repository | Port | CI Status | Docker Image |
|-----------|------------|------|-----------|--------------|
| **Frontend** | [duynhlab/frontend](https://github.com/duynhlab/frontend) | 3000 | [![CI](https://github.com/duynhlab/frontend/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/frontend/actions) | `ghcr.io/duynhlab/frontend/frontend` |

## 🛠️ Setup

To clone all repositories for local development, follow the instructions in [docs/platform/setup.md](docs/platform/setup.md).
