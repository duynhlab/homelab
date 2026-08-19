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
stack, database and secrets infra, and Kyverno policies. Deploys **10 Go
microservices** across five domains (identity, catalog, checkout, fulfillment,
comms), **two Temporal workers**, a React storefront, and a back-office portal
on **Kind** — with **Keycloak** for identity and **Envoy Gateway** as the only
edge. Application source lives in separate repositories.

---

## Topology

```mermaid
flowchart TD
    classDef edge fill:#2563eb,color:#fff,stroke:#1e3a8a;
    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef worker fill:#f59e0b,color:#451a03,stroke:#b45309;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    classDef external fill:#64748b,color:#fff,stroke:#334155;

    Browser["Browser"]:::external
    EG["Envoy Gateway<br/>gateway.duynh.me<br/>(TLS, JWT, CORS, rate-limit)"]:::edge
    KC["Keycloak<br/>id.duynh.me (OIDC)"]:::platform

    subgraph Apps ["Applications"]
        SPA["Storefront SPA<br/>local.duynh.me"]:::service
        BO["Back-office portal<br/>backoffice.duynh.me"]:::service
        SVC["10 Go services<br/>identity · catalog · checkout<br/>· fulfillment · comms"]:::service
        TMP["Temporal server"]:::platform
        WK["Temporal workers<br/>checkout-worker · order-worker"]:::worker
    end

    subgraph Data ["Data"]
        valkey[("Valkey cache")]:::data
        pgdog["PgDog pooler"]:::data
        pgb["CNPG pooler<br/>(PgBouncer)"]:::data
        productdb[("product-db<br/>CNPG HA + DR replica")]:::data
        platformdb[("platform-db<br/>CNPG HA")]:::data
    end

    subgraph Obs ["Observability"]
        direction LR
        otel["OTel Collector<br/>+ vmagent · Vector"]:::platform
        backends["VictoriaMetrics · VictoriaLogs<br/>Tempo · Pyroscope · ClickHouse"]:::platform
        grafana["Grafana<br/>+ Sloth SLOs"]:::platform
        otel --> backends --> grafana
    end

    subgraph Sec ["Secrets"]
        openbao["OpenBAO (HA Raft)"]:::platform
        eso["External Secrets Operator"]:::platform
        openbao --> eso
    end

    Browser -->|HTTPS| EG
    EG --> SPA & BO & SVC
    EG -.->|"JWKS"| KC
    SVC -->|"Cache-Aside"| valkey
    SVC --> TMP --> WK
    SVC -->|"catalog/checkout SQL"| pgdog ==> productdb
    SVC -->|"identity/comms SQL"| pgb ==> platformdb
    KC & TMP -->|"direct SQL"| platformdb
    SVC & WK -.->|"OTLP"| otel
    eso -.->|"secrets"| SVC
```

Colors follow the house palette: blue = edge, cyan = services, amber = workers,
purple = platform components, green = data stores, gray = external.

---

## Repository layout

| Path | Role |
|------|------|
| `kubernetes/clusters/` | Flux bootstrap + per-cluster `Kustomization` dependency chain |
| `kubernetes/infra/` | Controllers and configs — monitoring, databases, secrets, Envoy Gateway, Kyverno |
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

Kind maps host `80`/`443` to the Envoy Gateway NodePorts (`30080`/`30443`).
TLS is a wildcard `*.duynh.me` cert — self-signed `homelab-ca` on local Kind
(browser warning); Let's Encrypt on prod.

| URL | Purpose |
|-----|---------|
| https://local.duynh.me | Storefront SPA |
| https://gateway.duynh.me | API gateway |
| https://id.duynh.me | Keycloak (OIDC) |
| https://backoffice.duynh.me | Back-office portal |
| https://grafana.duynh.me | Dashboards |
| https://temporal.duynh.me | Temporal UI |
| https://ui.duynh.me | Flux UI |

Demo login: `alice` / `password123` (by username).

---

## Local stack

Without Kubernetes, validate the exact source candidate before creating a
release tag:

```bash
cd local-stack && docker compose up -d --build
```

SPA at http://localhost:3001, gateway at http://localhost:8080. The
[full E2E release audit](local-stack/docs/e2e-audit.md) must pass before the
candidate is tagged and pinned for Kind.

---

**Built with ❤️.**
