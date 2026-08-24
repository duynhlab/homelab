# Platform delivery

GitOps bring-up, application delivery (ResourceSets), the Envoy Gateway edge, CI/CD policy, and
day-2 platform patterns for the duynhlab homelab.

| | |
|---|---|
| **Deployed today** | Kind cluster — `kubernetes/clusters/local/` (22 Flux Kustomizations) |
| **Applications** | 10 Go microservices + React frontend + back-office portal + Temporal workers (`order-worker`, `checkout-worker`) + `mockpay` |
| **GitOps** | Flux Operator + OCI artifacts + Kustomize — [`setup.md`](setup.md) |
| **App onboarding** | Domain ResourceSets + InputProviders — [`application-delivery.md`](application-delivery.md) |
| **Edge** | Envoy Gateway on the Gateway API — [`envoy-gateway.md`](envoy-gateway.md) |
| **Planned (not in homelab yet)** | Prod cluster overlay (`kubernetes/clusters/production/` stub); dev/uat branch CI promotion — see [`gitflow.md`](gitflow.md) + [`cicd.md`](cicd.md) callouts |

> **Homelab vs target:** docs in this folder describe both what runs on **local Kind
> today** and **policy targets** (prod TLS, dev→uat→main promotion). When a section
> reads operational but the prod cluster or CI wiring is not live, it is marked
> **planned** in the source doc or in the table below.

---

## Overview

Platform delivery splits into three layers:

1. **Bootstrap** — Kind + local OCI registry + OpenTofu Flux Operator install (`make up`).
2. **Reconcile** — Flux Kustomizations apply infra then apps in `dependsOn` order.
3. **Operate** — Kyverno admission, edge HTTPRoutes, observability, secrets sync, SLOs.

Application business logic and handlers live in separate service repos; homelab owns
manifests, GitOps pins, gateway routes, and the docs index.

## Flux dependency summary

Infra waves reconcile before apps. High-level order (full numbered graph in
[`setup.md`](setup.md#project-architecture)):

```mermaid
flowchart TD
    controllers["controllers-local<br/>operators + namespaces"]
    secrets["secrets-local<br/>bootstrap Job + ESO configs"]
    certmgr["cert-manager-local"]
    gwcrds["gateway-api-crds-local"]
    keycloak["keycloak-local<br/>duynhlab realm"]
    edge["envoy-gateway-local +<br/>envoy-gateway-config-local"]
    monitoring["monitoring-local<br/>observability configs + SLO CRs"]
    storage["storage-local"]
    clickhouse["clickhouse-local"]
    tracing["tracing-local + profiling-local"]
    databases["databases-local + DR"]
    temporal["temporal-local + temporal-config-local"]
    apps["apps-local<br/>ResourceSets + workers"]

    controllers --> secrets
    controllers --> certmgr
    controllers --> monitoring
    secrets --> certmgr
    controllers --> gwcrds
    gwcrds --> edge
    certmgr --> edge
    keycloak --> edge
    databases --> keycloak
    secrets --> keycloak
    monitoring --> keycloak
    controllers --> storage
    secrets --> storage
    controllers --> clickhouse
    secrets --> clickhouse
    clickhouse --> tracing
    secrets --> tracing
    storage --> tracing
    secrets --> databases
    monitoring --> databases
    databases --> temporal
    monitoring --> temporal
    databases --> apps
    monitoring --> apps
    temporal --> apps
```

This diagram is a summary — the full numbered graph of all 22 Kustomization CRs
lives in [`setup.md`](setup.md#project-architecture).

`make flux-sync` (inside `make sync`) reconciles only a **subset** of Kustomizations
— see [`setup.md`](setup.md) for the caveat. After infra-only changes, reconcile the
specific Kustomization or run `make sync`.

---

## Document map

| Doc | When to read |
|-----|----------------|
| [`setup.md`](setup.md) | First bring-up, Makefile commands, hosts, seed data, full Flux graph, project tree |
| [`kind-e2e-audit.md`](kind-e2e-audit.md) | **The Kind cluster gate** — K0–K6 runbook proving Flux delivered the pinned images, admission, the real edge, and cluster-only telemetry. Twin of the [Compose E2E audit](../../local-stack/docs/e2e-audit.md) |
| [`application-delivery.md`](application-delivery.md) | Add a service, ResourceSet contract, image pins, domain labels |
| [`envoy-gateway.md`](envoy-gateway.md) | The edge: resource model, policy attachment, both provider modes, failure modes |
| [`kong-gateway.md`](kong-gateway.md) | **Archived** — the previous gateway's guide, kept for reference |
| [`identity-cutover-runbook.md`](identity-cutover-runbook.md) | RFC-0024 P3 greenfield DB reset (string `user_id` + Keycloak realm) |
| [`cicd.md`](cicd.md) | Polyrepo CI standards, scan-before-push, signing targets |
| [`gitflow.md`](gitflow.md) | Branching and release policy (**target** — prod cluster TBD) |
| [`kyverno.md`](kyverno.md) | Admission policy tiers, Audit→Enforce, PolicyExceptions |
| [`mcp-servers.md`](mcp-servers.md) | VictoriaMetrics/Logs/Flux/Grafana MCP servers for AI-assisted ops |
| [`sonarcloud.md`](sonarcloud.md) | Per-repo SonarCloud keys and coverage gates |
| [`ruleset-automation.md`](ruleset-automation.md) | Org-wide GitHub Ruleset automation via gh-patcher |
| [`gke-internal-dns.md`](gke-internal-dns.md) | **Reference only** — GKE + Cloud DNS patterns; not homelab topology |

Workflow templates (not prose docs): `build_template.yml`, `check_template.yml`.

---

## References

- [`kubernetes/clusters/local/`](../../kubernetes/clusters/local/) — Flux Kustomization CRs
- [`kubernetes/infra/`](../../kubernetes/infra/) — controllers + configs
- [`kubernetes/apps/`](../../kubernetes/apps/) — ResourceSets and InputProviders
- [`terraform/README.md`](../../terraform/README.md) — Flux Operator bootstrap

_Last updated: 2026-08-22 — RFC-0026/ADR-054: the Temporal Worker Controller owns the versioned-worker lifecycle, so `order-worker` is one `WorkerDeployment` and the build id is derived rather than named here. Previously 2026-08-21 — order-worker moved to build `2.4.0` (Temporal SDK v1.48.0; the frozen `1.13.2` had no arm64 leg) and the Kind E2E audit runbook joined the doc map. Previously 2026-08-19 — synced to the deployed platform (22 Kustomizations, back-office portal, `order-worker-1-13-2`, keycloak → monitoring edge)._
