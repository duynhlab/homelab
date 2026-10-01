# ADR-080: Keep Agent Workers Tokenless and Publish through a Trusted Boundary

> **Decision summary:** We will keep implementation workers without GitHub
> write credentials and separate patch generation from repository publishing.
> We accept a human publishing step in the first phases in exchange for a real
> least-privilege boundary outside the prompt.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-10-01 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | Identity, credentials, repository scope, and the trusted publishing boundary for RFC-0033 |
| **Affected components** | Planned workers, verifier, trusted publisher, GitHub App, repository rules |
| **Related RFC** | [RFC-0033](../../rfc/RFC-0033/) |
| **Related research** | [research.md](../../rfc/RFC-0033/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0033 Phases 0–1; unattended publishing is deferred |
| **Adoption** | Not started |

## Context

Worktree isolation prevents agents from overwriting each other's files, but it
does not constrain the credentials available to a process. Claude subagents
share the parent session's credentials, and Claude routines act through the
linked user's identity. A persona, prompt, or clean context is therefore not a
security boundary.

GitHub App `contents:write` is repository-wide rather than path-scoped. An
unattended publisher needs an external check that the full patch still matches
the exact task revision the owner authorized.

## Scope

### In scope

- Credentials available to workers and verifiers.
- The initial human publishing path.
- The permission envelope and qualification bar for a future GitHub App publisher.

### Out of scope

- Task record structure, owned by [ADR-079](../ADR-079-version-agent-task-contracts/).
- Lease and trigger behavior, owned by [ADR-081](../ADR-081-agent-leases-and-reconciliation/).
- Registering an App, creating secrets, or enabling an unattended write path in this decision PR.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Least privilege | Untrusted content and model mistakes must not inherit owner-wide write authority |
| 2 | Scope enforcement | Repository permissions do not enforce task-specific paths |
| 3 | Auditability | A reviewer must know which identity generated and which identity published a change |
| 4 | Reversibility | Publishing authority must be independently revocable |

## Decision

Workers and verifiers will receive a read-only checkout and no GitHub write
token. They produce a patch and evidence bundle. During Phases 0 and 1, a human
reviews that output, pushes the branch, and opens the draft pull request.

Unattended repository writes remain disabled until a dedicated GitHub App and
trusted publisher pass their negative tests. The App will be installed per
repository and use short-lived installation tokens available only to the
publisher. The publisher validates the complete patch against the authorized
task revision, checksum, immutable base SHA, allowed and forbidden paths, and
destination branch before requesting a token or writing anything.

The candidate App permission envelope is:

| Capability | Maximum permission |
|------------|--------------------|
| Repository contents, issues, pull requests | Write only where the publisher flow requires it |
| Checks and commit statuses | Read |
| Actions and workflow artifacts | Read only when an accepted evidence flow proves the need |
| Administration and workflow definitions | None |

Claude routines using the owner's linked GitHub identity remain read-only
qualification or trigger surfaces. They do not receive unattended publishing
authority.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Worker identity** | No GitHub write token, App private key, owner token, or deploy credential enters a worker or verifier context |
| **Initial publishing** | A human publishes Phase 0–1 output after reviewing the full patch and evidence |
| **Future publishing** | Only a qualified publisher may obtain a short-lived App installation token |
| **Path boundary** | Publisher validates the complete diff; prompt instructions are not enforcement |
| **Forbidden authority** | No agent identity may approve, merge, release, deploy, reconcile Flux, rotate secrets, delete data, or loosen policy |
| **Guardrail changes** | Instructions, schemas, hooks, permissions, and CI change only through a normal human-reviewed PR |
| **Failure behavior** | Scope, base, checksum, branch, or diff ambiguity stops publishing before token acquisition |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Tokenless workers; human publish first; App later** | Real separation, smallest initial blast radius, reversible | More human effort in Phase 0–1 | Selected |
| **B — Give workers an App token** | Direct branch and PR creation | A compromised worker can write anywhere the installation permits | Rejected |
| **C — Use the owner's linked Claude identity** | Fastest setup and attributable to the owner | Broad personal authority and weak separation | Rejected |
| **D — Build a custom identity service now** | Strongest bespoke control | Adds an operating service before evaluation proves a need | Rejected |

### Why the selected option won

It lets the project prove task quality and evidence before introducing any
unattended write credential. The later App path remains possible without
changing worker contracts.

### Why the closest alternative lost

A GitHub App improves token lifetime and repository scope but does not provide
path scope. Giving its token directly to a worker would bypass the full-diff
validation that makes the boundary useful.

## Consequences

### Positive consequences

- Prompt injection in a worker cannot directly write to GitHub.
- App revocation can stop publishing without changing task or worker logic.
- Generation, verification, publishing, and approval remain distinguishable.

### Negative consequences and accepted trade-offs

- Phase 0–1 retain a manual push and draft-PR step.
- A trusted publisher and App permission matrix still need implementation and security review.
- Separate model context does not provide separate identity by itself.

### Neutral consequences

- Human merge authority remains unchanged.
- Agent-authored changes use the repository's existing branch protection and CI.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Prove workers and verifiers have no write credentials | `duynhne` | RFC-0033 Phase 0 | Negative tests cannot create issues, branches, authorization, or lease records |
| Document the Phase 1 human publishing handoff | `duynhne` | RFC-0033 Phase 1 | Patch and evidence can be reviewed and published without hidden state |
| Specify and test publisher full-diff validation | `duynhne` | Later RFC-0033 phase | Every declared scope/base/branch failure is rejected before token use |
| Qualify the per-repository GitHub App | `duynhne` | Later RFC-0033 phase | Endpoint permission matrix and credential-leak tests pass |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Tokenless execution | Worker environment and tool allowlist contain no GitHub write or deploy credential |
| Full-diff scope | Publisher rejects added, modified, renamed, copied, and deleted out-of-scope paths |
| Immutable base | A stale or mismatched base SHA blocks publishing |
| Authorization | Wrong revision or checksum blocks publishing |
| Permission floor | App cannot administer repositories, change workflows, merge, or access unrelated repositories |

## Revisit triggers

Re-open this decision when GitHub provides enforceable task-path credentials,
human publishing prevents Phase 1 from meeting its intervention bar, or a
separately accepted controller introduces a stronger workload-identity model.

## References

- [RFC-0033](../../rfc/RFC-0033/)
- [RFC-0033 research](../../rfc/RFC-0033/research.md)
- [ADR-079](../ADR-079-version-agent-task-contracts/)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-10-01 | Accepted / Not started | Architecture review accepted tokenless workers and human publishing for Phases 0–1 |

---
_Last updated: 2026-10-01 — Accepted, Adoption Not started_
