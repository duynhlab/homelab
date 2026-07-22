<div align="center">

<a name="readme-top"></a>

<img src=".github/.metadata/logo.png" alt="duynhlab homelab" width="120" height="auto">

<h1>duynhlab homelab</h1>

<p><em>Infrastructure, GitOps, and observability for the duynhlab microservices platform.</em></p>

<p>
  <a href="kubernetes/">Kubernetes</a>
  &middot;
  <a href="terraform/">OpenTofu</a>
  &middot;
  <a href="local-stack/">Local Stack</a>
</p>

<p>
  <a href="https://kind.sigs.k8s.io/"><img src="https://img.shields.io/badge/Kind-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kind"></a>&nbsp;
  <a href="https://fluxcd.io/"><img src="https://img.shields.io/badge/GitOps-Flux-5468ff?style=for-the-badge&logo=flux&logoColor=white" alt="Flux"></a>&nbsp;
  <a href="https://opentofu.org/"><img src="https://img.shields.io/badge/OpenTofu-7B42BC?style=for-the-badge&logo=opentofu&logoColor=white" alt="OpenTofu"></a>&nbsp;
  <a href="https://github.com/duynhlab/homelab/actions/workflows/ci.yml"><img src="https://github.com/duynhlab/homelab/actions/workflows/ci.yml/badge.svg" alt="CI"></a>&nbsp;
  <a href="https://github.com/duynhlab/homelab/actions/workflows/renovate.yml"><img src="https://github.com/duynhlab/homelab/actions/workflows/renovate.yml/badge.svg" alt="Renovate"></a>
</p>

</div>

---

## Overview

Platform delivery hub: Kubernetes manifests (Flux + Kustomize + OCI), observability
stack, database and secrets infra, and Kyverno policies. Deploys **10 Go microservices**
and a React frontend on **Kind** locally. Application source lives in separate
repositories.

---

## Topology

```mermaid
flowchart TD
    classDef frontend fill:#3b82f6,stroke:#1d4ed8,stroke-width:2px,color:#fff,rx:8px,ry:8px
    classDef layer    fill:#10b981,stroke:#047857,stroke-width:2px,color:#fff,rx:5px,ry:5px
    classDef cache    fill:#f59e0b,stroke:#b45309,stroke-width:2px,color:#fff,rx:5px,ry:5px
    classDef pooler   fill:#8b5cf6,stroke:#5b21b6,stroke-width:2px,color:#fff,rx:5px,ry:5px
    classDef database fill:#ef4444,stroke:#b91c1c,stroke-width:2px,color:#fff
    classDef obs      fill:#1e293b,stroke:#0f172a,stroke-width:2px,color:#fff,rx:5px,ry:5px
    classDef obsGroup fill:#f1f5f9,stroke:#94a3b8,stroke-width:2px,stroke-dasharray:5 5,rx:10px,ry:10px
    classDef secret   fill:#ec4899,stroke:#be185d,stroke-width:2px,color:#fff,rx:5px,ry:5px
    classDef servicebox fill:#f8fafc,stroke:#cbd5e1,stroke-width:2px,stroke-dasharray:5 5,rx:10px,ry:10px

    FE["Frontend<br/>local.duynh.me"]:::frontend
    Kong["Kong Ingress<br/>gateway.duynh.me<br/>(TLS, CORS, rate-limit)"]:::layer

    subgraph Microservices ["10 microservices · Web → Logic → Core"]
        WebLayer["Web<br/>(HTTP, validation, aggregation)"]:::layer
        LogicLayer["Logic<br/>(business rules, Cache-Aside)"]:::layer
        CoreLayer["Core<br/>(domain models, repositories)"]:::layer
        WebLayer --> LogicLayer --> CoreLayer
    end

    subgraph Observability ["Observability stack"]
        direction LR
        prom["VictoriaMetrics"]:::obs
        tempo["Tempo + OTel"]:::obs
        vlogs["VictoriaLogs + Vector"]:::obs
        pyro["Pyroscope"]:::obs
        grafana["Grafana"]:::obs
        prom & tempo & vlogs & pyro --> grafana
    end

    subgraph CoreInfra ["Core infrastructure"]
        direction LR
        valkey["Valkey cache"]:::cache
        subgraph SecretsDev ["Secrets"]
            openbao["OpenBAO (HA Raft)"]:::secret
            eso["External Secrets Operator"]:::secret
            openbao --> eso
        end
    end

    subgraph Poolers ["Connection poolers (PgDog)"]
        pdog_product["pgdog-product"]:::pooler
        pdog_auth["pgdog-auth"]:::pooler
        pdog_shared["pgdog-shared"]:::pooler
    end

    subgraph Databases ["PostgreSQL (CloudNativePG, HA)"]
        db_product[("product-db<br/>CNPG (+ DR replica)")]:::database
        db_auth[("auth-db<br/>CNPG")]:::database
        db_shared[("shared-db<br/>CNPG")]:::database
        db_temporal[("temporal-db<br/>CNPG")]:::database
    end

    FE -->|HTTPS| Kong --> WebLayer
    WebLayer & LogicLayer & CoreLayer -.->|telemetry| Observability
    LogicLayer -->|Cache-Aside| valkey
    eso -.->|secrets| Databases
    eso -.->|secrets| CoreLayer
    CoreLayer -->|SQL product/cart/order/payment| pdog_product
    CoreLayer -->|SQL auth| pdog_auth
    CoreLayer -->|SQL user/review/shipping/notification| pdog_shared
    pdog_product ==> db_product
    pdog_auth ==> db_auth
    pdog_shared ==> db_shared

    class Microservices,SecretsDev servicebox
    class Observability obsGroup
```

---

## Repository layout

| Path | Role |
|------|------|
| `kubernetes/clusters/` | Flux bootstrap + per-cluster `Kustomization` dependency chain |
| `kubernetes/infra/` | Controllers and configs — monitoring, databases, secrets, Kong, Kyverno |
| `kubernetes/apps/` | Domain ResourceSets and per-service InputProviders |
| `terraform/` | OpenTofu bootstrap of Flux Operator + `FluxInstance` |
| `local-stack/` | Docker Compose e2e stack (no cluster required) |
| `docs/` | Platform documentation |
| `scripts/` | Kind, Flux, and validation helpers (Makefile targets) |

---

## GitOps delivery

Manifests are built with Kustomize, published as OCI artifacts, and reconciled by
the Flux Operator. Infra must reconcile before apps (`dependsOn` in
`kubernetes/clusters/local/`).

```mermaid
flowchart LR
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;

    Git["Git (homelab)"] --> Push["make flux-push<br/>OCI registry"]
    Push --> Flux["Flux Operator"]:::platform
    Flux --> Infra["kubernetes/infra"]:::platform
    Infra --> Apps["kubernetes/apps"]:::service
```

---

## Quick start

```bash
make prereqs                  # check kind, kubectl, flux, helm, docker, tofu
sudo scripts/setup-hosts.sh   # *.duynh.me → 127.0.0.1
make up                       # Kind + OCI push + Flux bootstrap
make flux-status              # watch reconciliation (~5–10 min first time)
```

Other targets: `make validate`, `make sync`, `make down`, `make help`.

---

## Local access

Kind maps host `80`/`443` to Kong. TLS is a wildcard `*.duynh.me` cert — self-signed
`homelab-ca` on local Kind (browser warning); Let's Encrypt on prod.

| URL | Purpose |
|-----|---------|
| https://local.duynh.me | Frontend SPA |
| https://gateway.duynh.me | API gateway |
| https://grafana.duynh.me | Dashboards |
| https://ui.duynh.me | Flux UI |

Demo login: `alice` / `password123` (by username).

---

## Local stack

Without Kubernetes:

```bash
cd local-stack && docker compose up -d --build
```

SPA at http://localhost:3001, gateway at http://localhost:8080.

---

**Built with ❤️.**
