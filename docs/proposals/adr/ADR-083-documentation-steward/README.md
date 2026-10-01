# ADR-083: Govern Platform Documentation through a Documentation Steward

> **Decision summary:** We will treat `docs/` as an executable learning and
> knowledge plane, with a Documentation Steward enforcing reader contracts and
> evidence while domain owners retain technical authority. We accept templates,
> independent review, and example classification in exchange for documentation
> that can teach and remain trustworthy from junior to platform owner.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-10-01 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | Content contracts, review authority, learning routes, and executable-example policy for Homelab documentation |
| **Affected components** | Planned Documentation Steward, `docs/_templates/`, `platform-engineer` skill, docs CI, `docs/observability/` pilot |
| **Related RFC** | [RFC-0033](../../rfc/RFC-0033/) |
| **Related research** | [research.md](../../rfc/RFC-0033/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0033 Phase 0 documentation evals and the observability pilot |
| **Adoption** | Not started |

## Context

Homelab documentation already serves as platform truth for agents and people,
but pages can mix onboarding, task steps, exact reference, and architectural
explanation. That makes a page difficult to verify and forces both beginners
and experienced operators through the same reading path.

Generated documentation can amplify stale counts, copied contracts, unsafe
commands, and plausible claims that do not match manifests. Editorial quality
alone cannot establish technical truth, while domain review alone does not
guarantee a usable learning path.

## Scope

### In scope

- The four reader contracts and junior-to-owner capability route.
- Documentation Steward and domain-owner review boundaries.
- Classification of fenced command examples by execution safety.
- The initial `docs/observability/` capability-map pilot.

### Out of scope

- Rewriting every existing page or imposing one universal page layout.
- Allowing the Steward to redefine APIs, deployed behavior, or design decisions.
- Implementing templates, metadata lint, or executable-docs CI in this architecture PR.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Technical truth | Humans and agents make platform changes from these documents |
| 2 | Reader success | Junior and expert readers need different paths through the same knowledge |
| 3 | Executable evidence | Commands, links, diagrams, and status claims must be reproducible |
| 4 | Clear authority | Editorial review must not replace the technical owner |

## Decision

Every new or materially changed documentation page will have one dominant
reader contract:

| Contract | Reader question | Required shape |
|----------|-----------------|----------------|
| **Tutorial** | Can you help me achieve a first success? | Prerequisites, safe sequence, checkpoints, expected observations, cleanup, and next step |
| **How-to** | How do I accomplish or recover from this task? | Goal, assumptions, direct steps, verification, failure handling, and related reference |
| **Reference** | What is the exact contract or value? | Structured facts mirroring the system, ownership, version/status, and lookup-oriented navigation |
| **Explanation** | Why does the system work this way? | Mental model, mechanisms, trade-offs, failure behavior, evidence, and links to exact reference |

The Documentation Steward owns classification, learning design, clarity,
accessibility, navigation, provenance, and evidence review. The relevant domain
owner approves technical claims. For high-impact operational, security,
database, or release guidance, the same worker cannot be the sole author and
verifier. The Steward cannot redefine a contract or approve its own changes.

Four planned Markdown templates under `docs/_templates/` will own these reader
contracts. The existing `platform-engineer` skill will point to them; Homelab
will not create a second project documentation skill. Area hubs curate routes
through orientation, first success, independent work, fluent lookup, deep
understanding, and ownership rather than exposing only the directory tree.

An HTML marker immediately before a fenced block classifies executable examples:

```markdown
<!-- example-policy: ci-safe -->
```

Allowed values are `ci-safe`, `ephemeral`, and `review-only`. The marker applies
to the entire following block. A missing marker means `review-only`.
Destructive commands, production access, secret rotation, Flux reconciliation,
and real-data mutation are always review-only and never execute from docs CI.

`docs/observability/` is the first capability-map pilot. Broken links, missing
area/global index entries, Mermaid rendering, and deployed/planned labels form
the deterministic canary. A semantic count or status correction additionally
requires a canonical source, reproducible command/query, and domain-owner verdict.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **One dominant contract** | A page serves tutorial, how-to, reference, or explanation; mixed purposes split and cross-link |
| **Technical authority** | Manifests, code, API contracts, RFC/ADR state, and executable evidence outrank generated prose |
| **Review separation** | Domain owner approves truth; Steward approves learning design and evidence |
| **Status language** | Deployed, planned, reference, and historical state are explicit and follow repository rules |
| **Example safety** | Untagged blocks are review-only; destructive or real-system mutation never runs from docs CI |
| **Navigation** | New canonical pages appear in their area hub and the global docs index with intentional next steps |
| **No duplication** | Exact API and platform facts link to their canonical owner rather than creating competing copies |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Four contracts + Steward/domain-owner split** | Serves distinct reader needs and preserves technical authority | Adds templates, review work, and evidence discipline | Selected |
| **B — One house template for every page** | Simple and visually consistent | Mixes incompatible reader goals and creates oversized guides | Rejected |
| **C — Domain-owner review only** | Strong subject expertise | Learning design, accessibility, navigation, and runnable examples remain inconsistent | Rejected |
| **D — Autonomous documentation publisher** | High output volume | Can publish stale or invented truth without accountable review | Rejected |

### Why the selected option won

It separates two independent quality questions: whether a claim is technically
true and whether a reader can learn, act, find exact facts, and reason from the
page. Neither reviewer silently inherits the other's authority.

### Why the closest alternative lost

One universal template would be easy to lint but would recreate the mixed-page
problem. Tutorials and reference pages need different structures even when they
cover the same platform area.

## Consequences

### Positive consequences

- New engineers get reliable first-success routes without hiding expert reference.
- Documentation claims remain tied to canonical repository or executable evidence.
- Command safety and independent review become explicit and testable.

### Negative consequences and accepted trade-offs

- Authors must classify intent before writing and sometimes split existing pages.
- High-impact docs require two distinct review concerns.
- Executable-example CI must maintain safe environment boundaries.

### Neutral consequences

- Existing pages are improved when materially changed; no tree-wide rewrite is required.
- Mermaid remains the default diagram format under repository conventions.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Add four source templates under `docs/_templates/` | `duynhne` | RFC-0033 documentation pilot | Each contract states audience, prerequisites, outcome, evidence, and next step |
| Point `platform-engineer` to the templates | `duynhne` | RFC-0033 documentation pilot | One project skill remains the operating procedure |
| Build example-marker and navigation checks | `duynhne` | RFC-0033 Phase 0/pilot | Unsafe or unclassified executable behavior fails closed |
| Pilot the capability map in `docs/observability/` | `duynhne` | RFC-0033 Phase 1 canary | Reader routes, deterministic checks, and task-success evidence are recorded |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Reader contract | Seed a mixed-purpose page and require classification or split |
| Technical truth | Seed stale deployed/planned status and require canonical evidence plus owner verdict |
| Example safety | Verify untagged/destructive blocks never execute; safe fixtures run in their declared environment |
| Navigation | Link and orphan checks cover area hub, global index, and next-reading paths |
| Diagrams | Render every changed Mermaid block and inspect clipping, crossings, legend, and state labels |

## Revisit triggers

Re-open this decision when the observability pilot shows the four contracts do
not improve representative reader tasks, metadata adds review cost without
preventing drift, or executable examples cannot be isolated safely.

## References

- [RFC-0033](../../rfc/RFC-0033/)
- [RFC-0033 research](../../rfc/RFC-0033/research.md)
- [Documentation index](../../../README.md)
- [Platform-engineer skill](../../../../.agents/skills/platform-engineer/SKILL.md)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-10-01 | Accepted / Not started | Architecture review accepted the four content contracts, review split, and safe-example policy |

---
_Last updated: 2026-10-01 — Accepted, Adoption Not started_
