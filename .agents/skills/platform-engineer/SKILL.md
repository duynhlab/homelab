---
name: platform-engineer
description: >-
  The homelab owner's operating procedure for GitOps, Kubernetes,
  observability, databases, secrets, security, gateway and API contracts, and
  the owner's standing working rules. Use for non-trivial work in this repo;
  it routes docs to homelab-docs, design records to homelab-proposals,
  incidents to homelab-troubleshooting, and application code and shared CI to
  their owning repositories.
metadata:
  version: "3.0.0"
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
| `duynh` (workloads) and `slo` charts / Helm templates | `duynhlab/helm-charts` |
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
   only when the request includes implementation. Before starting or resuming
   tracked work, read [work tracking](../../../docs/platform/work-tracking.md):
   find the existing issue, its next action, blockers, and completion evidence.
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

## Working with the owner

This skill speaks for the platform owner (`duynhne`). These rules come from
corrections the owner made; each is binding for every agent in this repo.

1. **Gate, then merge, then tag.** PR → compose E2E audit
   ([`local-stack/docs/e2e-audit.md`](../../../local-stack/docs/e2e-audit.md))
   on the PR head SHA → merge → tag → pin → Kind as the single final pass.
   Never call a gated PR mergeable before its audit has passed. Check that the
   stack built the PR's SHA, not a stale sibling checkout.
2. **Never report green mid-push.** While commits are still coming to a
   branch, say so ("more commits coming, do not merge"). The owner merges
   fast, and a squash takes only what is on the branch at that moment.
3. **Admin merge only on green.** The rulesets require a review nobody else
   can give, so `gh pr merge --squash --admin` is authorised, but only after
   every required check passed. Never bypass CI.
4. **Stage named paths only.** Never `git add -A`, `git add .` or a
   directory: the owner keeps untracked notes in these repos.
5. **Evidence, not memory.** Versions, defaults and especially "X cannot do
   Y" claims come from Context7 or the unpacked artifact (chart, image,
   binary), not from training data, release notes or an earlier review. Put
   the upstream evidence (issue, PR, maintainer quote) in the ADR.
6. **Read the service's code.** Sibling repos are checked out next to
   homelab (`../<name>-service`, `../pkg`). For what a binary reads or wires,
   read its Go source; manifest comments describe intent, not behaviour.
7. **An adoptable feature holds the bump.** A dependency release with a
   capability homelab would adopt only by changing the repo is held, and the
   choice goes to the owner as a decision in the audit issue. UI-only
   features do not hold a bump.
8. **Pre-deployment platform.** Nothing runs in production yet: `docs/api/`
   states the target contract, and changes cut over clean, with no
   compatibility windows or deprecation staging. Runbooks still describe what
   runs today.
9. **Envoy-Gateway-native edge.** Design the edge for Envoy Gateway and the
   Gateway API; Kong is archived history, not a parity target.
10. **Explain the mechanism.** The owner works as architect and operator and
    learns from the docs. Explain how a thing works with the platform's own
    components as the example, and answer conformance questions ("do we do it
    like upstream?") against upstream docs. Chat replies may follow the
    owner's language; repository text stays English.

## RFC / ADR gate

Design **before** building when the change is substantial or contested; a bug,
cleanup, dependency bump, or narrow documentation correction uses a focused PR.
When a design record is the gate, read
[homelab-proposals](../homelab-proposals/SKILL.md) — it routes the RFC/ADR
lifecycle to its owning files. When to write an RFC at all:
[`rfc/README.md` § When to write an RFC](../../../docs/proposals/rfc/README.md).
Hub: [`docs/proposals/`](../../../docs/proposals/).

## Verification and release

- Before ending tracked work, update the existing issue with evidence, remaining
  work, and the next action. Set Project Status using
  [work tracking](../../../docs/platform/work-tracking.md#complete-and-resume-work).
  Keep Verification open when implementation landed but its gate did not pass.

- Before completing a change, apply [AGENTS.md's documentation and comment
  conventions](../../../AGENTS.md#docs-conventions) to the touched sections.
  Consolidate explanations, keep evidence with its claim, and use Git/PR history
  for the editing narrative. Preserve operational constraints and tooling directives.
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

When writing or reviewing branch names, commit messages, squash messages, or
PR titles and descriptions, read [git-pr](../git-pr/SKILL.md). For worktree lifecycle and cleanup
(including proving a squash-merged branch landed before deletion), read
[git-worktrees](../git-worktrees/SKILL.md). The PR workflow and Git/GitHub
identity remain in [AGENTS.md § Contribution workflow](../../../AGENTS.md#contribution-workflow).

## IDE skills map

Generic workflows live in the **agent IDE** ([addyosmani/agent-skills](https://github.com/addyosmani/agent-skills)). Use an available skill when its specific workflow applies; the table does not prescribe a sequence for every task. This project skill lives in `.agents/skills/platform-engineer/` and Claude Code reads the same file through `.claude/skills/platform-engineer`.

| Homelab work | IDE skill | Homelab gate |
|--------------|-----------|--------------|
| Unclear ask | `interview-me`, `idea-refine` | — |
| Research, RFC, or ADR | [`homelab-proposals`](../homelab-proposals/SKILL.md); research runs in the [`proposals-researcher`](../../agents/proposals-researcher.md) sub-agent | Owner OK RFC #, `docs/proposals/` |
| Manifest / GitOps | `incremental-implementation`, `source-driven-development` | `make validate`, Flux `dependsOn` |
| Secrets / high stakes | `doubt-driven-development`, `security-and-hardening` | Kyverno catalog |
| Observability | `observability-and-instrumentation` | alert catalog + runbook |
| CI | `ci-cd-and-automation` | often `gha-workflows` |
| E2E Phase B | `agent-browser` | [e2e-audit Phase B](../../../local-stack/docs/e2e-audit.md#phase-b--real-browser-agent-browser-8-min) |
| Incident triage / debug-note cleanup | [`homelab-troubleshooting`](../homelab-troubleshooting/SKILL.md) decides what to do and where a finding goes | runbook index + `make validate` |
| GitOps incident | `gitops-cluster-debug` | `make flux-status` |
| Docs page, runbook or hub (writing the page) | [`homelab-docs`](../homelab-docs/SKILL.md) | AGENTS.md Docs conventions, hub link, `make validate` |
| Draw.io diagram (asked by name, or editing a `.drawio`) | [`homelab-drawio`](../homelab-drawio/SKILL.md) | Mermaid stays the default (AGENTS.md Diagrams) |
| Branch, commit, PR text | [`git-pr`](../git-pr/SKILL.md) | `type(scope):` subject, duynhne author, duynebot trailer |
| Before PR | `code-review-and-quality` | one change per branch |
| Worktree cleanup | [`git-worktrees`](../git-worktrees/SKILL.md) | prove landed before deleting |
| Rollout | `shipping-and-launch`, `deprecation-and-migration` | Flux chain + CHANGELOG |

**Homelab overrides** (win over generic skill defaults): RFC/ADR paths and owner
gates → [`homelab-proposals`](../homelab-proposals/SKILL.md); commits → above;
Kyverno/netpol/secrets → [AGENTS.md](../../../AGENTS.md); API truth →
**`docs/api/`** whole tree.
