# ADR-090: Keep the Documentation Procedure in a Dedicated homelab-docs Skill

> **Decision summary:** We will keep the procedure for writing, editing and
> reviewing documentation in the `homelab-docs` project skill, with
> `platform-engineer` as the dispatcher that routes to it, because one skill
> carrying both the operating procedure and the writing procedure stopped
> fitting in an agent's working context. We accept a second project skill in
> exchange for a docs procedure an agent loads only when it writes a page.

| Attribute | Value |
|-----------|-------|
| **Status** | Proposed |
| **Decision date** | — |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | Where the homelab documentation procedure lives among the project skills |
| **Affected components** | `.agents/skills/homelab-docs/`, `.agents/skills/platform-engineer/`, ADR-083 |
| **Related RFC** | [RFC-0033](../../rfc/RFC-0033/) |
| **Related research** | [research.md](../../rfc/RFC-0033/research.md) |
| **Supersedes** | [ADR-083](../ADR-083-documentation-steward/) in part: only the clause "Homelab will not create a second project documentation skill" |
| **Superseded by** | — |
| **Implementation tracking** | Opened when the owner accepts this ADR |
| **Adoption** | Partial — the skill shipped in #1474; it does not yet point to the planned `docs/_templates/` |

## Context

ADR-083 decided the four reader contracts, the Documentation Steward and
domain-owner review split, and the example-safety markers. It also said that
the existing `platform-engineer` skill would point to four planned templates
under `docs/_templates/`, and that Homelab would not create a second project
documentation skill.

Since then, `platform-engineer` has become a dispatcher. Its RFC/ADR procedure
moved to `homelab-proposals` (#1472) and its commit and PR text to `git-pr`
(#1473). The docs procedure (page shapes, style rules, an editing workflow, a
five-pass review and a prose pass) is about 430 lines of references. Putting
it in `platform-engineer` would load it for every manifest change.

PR #1474 added `homelab-docs` as its own skill without recording that it
departs from ADR-083. `docs/_templates/` does not exist yet.

## Scope

### In scope

- Where the documentation writing, editing and review procedure lives.
- How `platform-engineer` and `homelab-docs` divide the work.

### Out of scope

- The four reader contracts, the Steward review split, the example-policy
  markers and the observability pilot. ADR-083 still decides these.
- The content of the planned `docs/_templates/`.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | One owner per procedure | Two copies of the docs rules drift, and reviewers enforce only one |
| 2 | Agent context cost | A procedure loaded on every task crowds out the task's own evidence |
| 3 | Consistency with the other skills | Proposals and Git text already have their own skills under the same dispatcher |

## Decision

We will keep the documentation procedure in `.agents/skills/homelab-docs/`.
`platform-engineer` stays the dispatcher. Its IDE skills map routes every page,
runbook and hub edit to `homelab-docs`, and it does not restate the docs rules.

`homelab-docs` builds on `AGENTS.md § Docs conventions` and does not copy it.
When the ADR-083 templates exist under `docs/_templates/`, `homelab-docs`
points to them; `platform-engineer` does not.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Ownership** | `homelab-docs` owns how a page is written, verified, edited and reviewed |
| **Dispatch** | `platform-engineer` routes docs work to `homelab-docs` and holds no docs procedure itself |
| **Conventions** | Repository-wide docs rules stay in `AGENTS.md`; the skill links them |
| **Boundary** | `homelab-proposals` owns research, RFC and ADR files; `homelab-troubleshooting` decides where an incident finding goes, and `homelab-docs` writes the page |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Dedicated `homelab-docs` skill** | Loaded only for docs work; one owner; matches the other split skills | A second project skill, against ADR-083's wording | Selected |
| **B — Fold the procedure into `platform-engineer`** | Keeps ADR-083 as written | Every task loads the docs procedure; undoes the dispatcher split | Rejected |
| **C — Templates only, no procedure** | Smallest footprint | The templates do not exist yet, and a template does not tell an agent how to verify or review | Rejected |

### Why the selected option won

It keeps one owner for the docs procedure and costs context only when an agent
writes docs, as `homelab-proposals` and `git-pr` already do.

### Why the closest alternative lost

Option B honours ADR-083's wording, but the reason for that wording was one
operating procedure. The dispatcher still provides that, so the extra skill
does not split authority.

## Consequences

### Positive consequences

- Agents load the docs procedure only when they edit docs.
- The rule for which skill owns a runbook edit is explicit.

### Negative consequences and accepted trade-offs

- There is one more project skill to version and keep in step with `AGENTS.md`.

### Neutral consequences

- ADR-083's obligation "Point `platform-engineer` to the templates" becomes
  "Point `homelab-docs` to the templates" once this ADR is accepted.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Ship `homelab-docs` and route to it from `platform-engineer` | `duynhne` | #1474 | Done |
| On acceptance, record the partial supersede in ADR-083 (Superseded by row, § Amendments) and in the ADR index | `duynhne` | Tracking issue | ADR-083 points to this ADR |
| Point `homelab-docs` to `docs/_templates/` when ADR-083 adds them | `duynhne` | RFC-0033 documentation pilot | `homelab-docs` links each template |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| One owner | `platform-engineer/SKILL.md` contains no docs procedure, only the routing row |
| No copied conventions | `homelab-docs` links `AGENTS.md § Docs conventions` instead of restating it |

## Revisit triggers

- `docs/_templates/` and the Steward tooling make the skill's references
  redundant.
- The project skills are merged back into one for another reason.

A changed decision requires a new ADR that supersedes this one.

## References

- [ADR-083](../ADR-083-documentation-steward/)
- [RFC-0033](../../rfc/RFC-0033/)
- [homelab-docs skill](../../../../.agents/skills/homelab-docs/SKILL.md)
- [platform-engineer skill](../../../../.agents/skills/platform-engineer/SKILL.md)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-11-01 | Proposed / Partial | Records the `homelab-docs` skill shipped in #1474 as a partial supersede of ADR-083 |
