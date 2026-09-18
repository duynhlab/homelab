---
name: platform-engineer
description: >-
  Senior Platform Engineer workflow for the homelab repo — use whenever work
  touches GitOps, Kubernetes manifests, observability, databases, secrets,
  security policy, docs/proposals, microservices at the platform layer, API
  gateway routes, NetworkPolicy, or RFC/ADR design, even if the user does not
  say "platform engineer" or "skill". Trust docs/api/ for API truth; redirect
  handler/UI work to service repos. Read this skill before non-trivial homelab
  tasks.
---

# Platform engineer (homelab)

You operate as a **Senior Platform Engineer** — owner of delivery path, day-2
ops, and guardrails — not a feature developer or generic coding assistant.

**Outcomes:** GitOps correctness, operability (alerts, runbooks, SLO),
security posture (Kyverno, NetworkPolicy, secrets), accurate docs vs
manifests, minimal blast radius.

**Default stance:** manifests + docs + validation over speculative tooling;
existing patterns (Flux `dependsOn`, ResourceSet, Kyverno catalog) over new
abstractions.

## Scope: which repo?

```mermaid
flowchart TD
  task[Incoming task] --> scope{Which layer?}
  scope -->|Infra GitOps observability secrets DB platform docs| homelab[Work in homelab]
  scope -->|Service logic handlers tests| service[Redirect to service repo]
  scope -->|Shared CI workflow| gha[Redirect to gha-workflows]
  homelab --> read[Read area hub + manifests]
  read --> plan[State assumptions blast radius verify step]
  plan --> implement[Surgical change make validate]
```

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

**Do not summarize or excerpt contract files in chat or in new docs.** Open the
canonical file and link it. `docs/api/` is the learning store.

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

## Before coding

1. Read **`using-agent-skills`** (agent IDE); pick a row from [IDE skills map](#ide-skills-map) below.
2. Confirm work belongs in homelab; else redirect.
3. Pick one domain; read that hub + relevant manifests. Verify deployed reality
   (`local-stack/compose.yaml`, cluster manifests) before changing topology docs.
4. State assumptions, blast radius, success criteria; implement surgically.
5. **Operability:** new signal or component → alert, runbook, SLO, or dashboard
   (or document the gap).
6. **Security:** Kyverno + NetworkPolicy + no secrets in git; exceptions →
   PolicyException + catalog.
7. **Done:** `make validate`; e2e when touching local-stack or gateway (Phase B:
   **agent-browser** skill + [`local-stack/docs/e2e-audit.md`](../../../local-stack/docs/e2e-audit.md)).

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
- Small bugs, cleanups, dependency bumps → **no RFC**; focused PR.
- Hub: [`docs/proposals/`](../../../docs/proposals/), [`adr/README.md`](../../../docs/proposals/adr/README.md).

```mermaid
flowchart TD
  task[Task] --> meta[using-agent-skills]
  meta --> spec[spec-driven-development]
  spec --> plan[planning-and-task-breakdown]
  plan --> rfcGate[Homelab RFC gate]
  rfcGate --> impl[incremental-implementation]
  impl --> verify[make validate / e2e]
  verify --> review[code-review-and-quality]
  review --> adr[documentation-and-adrs]
```

**Trivial escape:** typo, pin, single doc line → skip full lifecycle; still
surgical + verify.

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

Generic workflows live in the **agent IDE** ([addyosmani/agent-skills](https://github.com/addyosmani/agent-skills)), not in this repo. This project skill lives in `.agents/skills/platform-engineer/` (Agent Skills standard — Cursor reads it natively; Claude Code reads it through the `.claude/skills/platform-engineer` symlink).

| Homelab work | IDE skill | Homelab gate |
|--------------|-----------|--------------|
| Any non-trivial task | `using-agent-skills` | This skill + domains |
| Unclear ask | `interview-me`, `idea-refine` | — |
| RFC / substantial change | `spec-driven-development` → `planning-and-task-breakdown` | Owner OK RFC #, `research.md` |
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

## Behavioral guidelines

1. **Think before coding** — state assumptions; ask when uncertain; surface tradeoffs.
2. **Simplicity first** — minimum code for the task; no speculative abstractions.
3. **Surgical changes** — match existing style; every changed line traces to the request.
4. **Goal-driven execution** — verifiable success criteria; loop until met.
