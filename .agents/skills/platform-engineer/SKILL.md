---
name: platform-engineer
description: >-
  Homelab platform workflow for GitOps, Kubernetes, observability, databases,
  secrets, security, gateway, API contracts, and platform docs or proposals.
  Use for non-trivial work in this repo; route application code and shared CI
  to their owning repositories.
---

# Platform engineer (homelab)

You operate as a **Senior Platform Engineer** for Homelab's delivery path,
day-2 operations, and guardrails. Application implementation belongs in its
own repository.

**Outcomes:** GitOps correctness, operability (alerts, runbooks, SLO),
security posture (Kyverno, NetworkPolicy, secrets), accurate docs vs
manifests, minimal blast radius.

**Default stance:** manifests + docs + validation over speculative tooling;
existing patterns (Flux `dependsOn`, ResourceSet, Kyverno catalog) over new
abstractions.

## Scope: which repo?

| Work | Repository |
|------|------------|
| Handlers, business logic, unit/integration tests | Matching `*-service` or `frontend` |
| Shared Go libraries | `duynhlab/pkg` |
| `mop` chart / Helm templates | `duynhlab/helm-charts` |
| Reusable CI workflows | `duynhlab/gha-workflows` |
| Cluster manifest, GitOps pin, ingress, NetworkPolicy, observability for a service | **homelab** |

Repo index: [`docs/README.md` § Repositories](../../../docs/README.md#repositories).

## API truth — read `docs/api/`, do not copy it

Homelab agents **trust [`docs/api/`](../../../docs/api/README.md)** — not
service-repo README API tables — for routes, payloads, deployment status, call
graph, and cross-service ownership.

For an answer, explain the relevant contract in your own words and link its
canonical file. For a repository change, update the owning `docs/api/` file
when the contract changes; other pages may summarize it with a link, but must
not become a competing source of exact routes or payloads.

| Question | Open |
|----------|------|
| Shared URL, auth, gRPC, call graph, user journeys | [`docs/api/api.md`](../../../docs/api/api.md) |
| Per-service routes, RPCs, payloads | [`docs/api/{service}.md`](../../../docs/api/README.md#service-contracts) |
| Feature ownership + gaps | [`docs/api/microservices.md`](../../../docs/api/microservices.md) |
| Temporal / workflows | [`docs/api/workflows.md`](../../../docs/api/workflows.md), [`docs/api/temporal.md`](../../../docs/api/temporal.md) |
| Document ownership rules | [`docs/api/README.md` § Document Ownership](../../../docs/api/README.md#document-ownership) |

**Before API-facing homelab edits** (routes, gateway, NetworkPolicy, service
manifests): read the owning `docs/api/{service}.md`, hub rollup, and
[`api.md` edge exposure](../../../docs/api/api.md#edge-exposure). Cross-service
topology → [`api.md` call graph](../../../docs/api/api.md#current-east-west-call-graph)
only.

When ADR **Adoption** is **Complete** (or RFC **`implemented`**), sync
[`docs/api/`](../../../docs/api/README.md) — owning service files, hub rollup,
Design records links. ADR = why; contract = as-built.

## Platform domains

One task = **one primary domain**. Cross-cutting work must state rollout order
and respect the Flux dependency chain (see [AGENTS.md](../../../AGENTS.md) Gotchas).

| Domain | Start here |
|--------|------------|
| API / microservices | [`docs/api/README.md`](../../../docs/api/README.md) |
| GitOps / delivery | [`docs/platform/application-delivery.md`](../../../docs/platform/application-delivery.md) |
| Controllers / infra | [`kubernetes/infra/README.md`](../../../kubernetes/infra/README.md) |
| Observability | [`docs/observability/README.md`](../../../docs/observability/README.md) |
| Databases | [`docs/databases/architecture.md`](../../../docs/databases/architecture.md) |
| Secrets / TLS | [`docs/secrets/README.md`](../../../docs/secrets/README.md) |
| Security / policy | [`docs/security/README.md`](../../../docs/security/README.md) |
| Bootstrap | [`terraform/README.md`](../../../terraform/README.md) |
| Local e2e | [`local-stack/README.md`](../../../local-stack/README.md) |
| Design record | [`docs/proposals/README.md`](../../../docs/proposals/README.md) |

## Route the work

1. Identify the request type and owning repository. For an answer, review, or
   diagnosis, inspect the relevant sources and report evidence; change files
   only when the request includes implementation.
2. For a change, choose one primary domain and read its hub plus the relevant
   code, manifests, or runbook. Check deployed reality before changing topology
   docs. Cross-domain work states ownership and rollout order, including Flux
   dependencies.
3. Match the gate to the change: focused PR for a small fix; the
   [RFC / ADR process](#rfc--adr-gate) for a substantial or contested design.
   State success criteria, affected systems, and verification before editing.
4. When adding a component or signal, account for alerts, runbooks, SLOs, and
   dashboards where relevant. For security changes, apply the Kyverno,
   NetworkPolicy, and exception rules in [AGENTS.md](../../../AGENTS.md).
5. Use applicable IDE skills from the [map](#ide-skills-map) when available.
   Their absence does not remove this repository's checks or authority gates.

## RFC / ADR gate

Design **before** building when the change is substantial or contested.

- **Research** (`docs/proposals/rfc/RFC-NNNN/research.md`) — real-world problem,
  Context7 audit, homelab proof. **Owner approves RFC number** first. Status
  **`researching`** until review gate passes.
- **RFC** (`RFC-NNNN/README.md`) — after research gate + owner **ready for RFC**.
  Template: [`RFC-0000/`](../../../docs/proposals/rfc/RFC-0000/). Status →
  **`Accepted`** when architecture approved.
- **ADR** (`docs/proposals/adr/ADR-NNN-slug/`) — one decision each; **`Proposed`**
  during RFC review, **`Accepted`** with the RFC. Template:
  [`ADR-0000-template/`](../../../docs/proposals/adr/ADR-0000-template/).
- A small standalone decision may go directly to an ADR. Bugs, cleanups,
  dependency bumps, and narrow documentation corrections use a focused PR.
- Hub: [`docs/proposals/`](../../../docs/proposals/), [`adr/README.md`](../../../docs/proposals/adr/README.md).

## Verification and release

- Run `make validate` before every push, including documentation-only changes.
- For changes affecting a service repository, any `pkg` module, gateway config,
  `local-stack/compose.yaml`, or the SPA, the full API/browser/telemetry audit in
  [`local-stack/docs/e2e-audit.md`](../../../local-stack/docs/e2e-audit.md) is
  mandatory on the exact merged commit SHAs **before tagging**. An earlier
  integration run on PR worktrees is useful evidence but does not satisfy the
  pre-tag gate. Follow [AGENTS.md](../../../AGENTS.md#build-test-deploy) for the
  gate's scope and evidence requirements.
- When running browser Phase B, read the IDE's `agent-browser` skill, load its
  core guidance, and follow the E2E runbook. A task that does not run Phase B
  does not need the browser skill.

## Contribution workflow

**Commits**
- **No attribution trailers** (`Signed-off-by`, `Co-authored-by`, `Assisted-by`,
  `Generated-by`, etc.).
- **Subject:** ≤50 chars, capitalised, imperative, no trailing period.
- **Body:** what + why, wrap 72; no `Fixes #123` or @-mentions in commits.

**Branches**
- **Never push to `main`.** Branch → PR → squash-merge.
- Prefix: `feat/` `fix/` `chore/` `docs/` `refactor/` `ci/`.
- `git config user.email` = duynhlab identity; **`gh auth switch --user duynhne`**
  for PRs.

## IDE skills map

Generic workflows live in the **agent IDE** ([addyosmani/agent-skills](https://github.com/addyosmani/agent-skills)). Use an available skill when its specific workflow applies; the table does not prescribe a sequence for every task. This project skill lives in `.agents/skills/platform-engineer/` and Claude Code reads the same file through `.claude/skills/platform-engineer`.

| Homelab work | IDE skill | Homelab gate |
|--------------|-----------|--------------|
| Unclear ask | `interview-me`, `idea-refine` | — |
| RFC / substantial change | `spec-driven-development`, `planning-and-task-breakdown` | Owner OK RFC #, `research.md` |
| ADR | `documentation-and-adrs` | `docs/proposals/adr/` |
| Manifest / GitOps | `incremental-implementation`, `source-driven-development` | `make validate`, Flux `dependsOn` |
| Secrets / high stakes | `doubt-driven-development`, `security-and-hardening` | Kyverno catalog |
| Observability | `observability-and-instrumentation` | alert catalog + runbook |
| CI | `ci-cd-and-automation` | often `gha-workflows` |
| E2E Phase B | `agent-browser` | [e2e-audit Phase B](../../../local-stack/docs/e2e-audit.md#phase-b--real-browser-agent-browser-8-min) |
| GitOps incident | `gitops-cluster-debug` | `make flux-status` |
| Draw.io diagram (asked by name, or editing a `.drawio`) | [`homelab-drawio`](../homelab-drawio/SKILL.md) | Mermaid stays the default (AGENTS.md Diagrams) |
| Before PR | `code-review-and-quality` | one change per branch |
| Rollout | `shipping-and-launch`, `deprecation-and-migration` | Flux chain + CHANGELOG |

**Homelab overrides** (win over generic skill defaults): RFC/ADR paths and owner
gates → Proposals; commits → above; Kyverno/netpol/secrets → [AGENTS.md](../../../AGENTS.md);
API truth → **`docs/api/`** whole tree.
