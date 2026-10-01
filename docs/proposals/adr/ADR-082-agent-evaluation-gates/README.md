# ADR-082: Promote Agent Autonomy through Measured Evaluation Gates

> **Decision summary:** We will increase agent authority only after versioned
> evaluations meet explicit quality, safety, cost, and human-effort bars. We
> accept a slower rollout and observation windows in exchange for autonomy based
> on outcomes rather than PR volume or subjective confidence.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-10-01 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | Evaluation fixtures, metrics, promotion bars, reset rules, and telemetry privacy for RFC-0033 |
| **Affected components** | Planned eval harness, evidence records, promotion report, minimal run metrics |
| **Related RFC** | [RFC-0033](../../rfc/RFC-0033/) |
| **Related research** | [research.md](../../rfc/RFC-0033/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0033 Phases 0–4 |
| **Adoption** | Not started |

## Context

Agent throughput is easy to inflate with small or rejected pull requests. It
does not show whether changes are correct, safe, economical, independently
reproducible, or less demanding of the owner. Expanding autonomy without stable
denominators would optimize activity while hiding rework and escaped defects.

Homelab needs promotion criteria fixed before a phase begins, plus versioned
negative cases that prevent prompt injection, retry-until-green, missing scope,
and stale evidence from being counted as success.

## Scope

### In scope

- Metric definitions and promotion thresholds for RFC-0033 phases.
- Required evaluation scenarios and observation/reset rules.
- Privacy and cardinality constraints for run telemetry.

### Out of scope

- Implementing the eval runner or dashboards in this architecture PR.
- Application or platform availability SLOs.
- Auto-merge or broader deployment authority.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Safety and correctness | Faster output is harmful when defects or authority violations escape |
| 2 | Reproducibility | Promotion must be supported by versioned fixtures and machine-checkable bars |
| 3 | Owner leverage | Automation must reduce active routing and review work |
| 4 | Economic visibility | Failed and abandoned runs must count toward cost |

## Decision

Every eval fixture will version its inputs, expected decisions, allowed tools,
cost ceiling, and machine-checkable pass bar. Promotion reports include all
runs, retries, failures, and abandoned work. PR count is not a success metric.

The normative metric definitions are:

| Metric | Definition |
|--------|------------|
| **First-pass gate** | Every predeclared deterministic check passes on the first pushed candidate without worker follow-up |
| **Rework** | A human requests a correctness, scope, security, or contract change; formatting-only edits do not count |
| **Escaped defect** | A merged change needs correction or revert because an acceptance criterion, contract, or safety boundary was wrong |
| **Human intervention** | Active routing and review minutes, excluding CI wait time |
| **Accepted candidate** | A human-merged Phase 1 PR whose seven-day observation window ends without an escaped defect |
| **Matched baseline** | At least ten human-run tasks in the same repository, task class, and risk bucket, using the same active-minute definition |
| **Reconciliation cycle** | One completed hourly scan of all ledger events after the previous monotonic watermark |

Promotion bars are fixed as follows:

| Promotion | Required evidence |
|-----------|-------------------|
| **Phase 0 → 1** | All ten versioned evals pass twice; at most 10% of all seeded negative assertions across those 20 runs are incorrectly reported as findings |
| **Phase 1 → 2** | Ten consecutive accepted candidates; at least 80% first-pass gates; at most 20% rework; zero escaped defects; median human minutes at most half the matched baseline |
| **Phase 2 → 3** | Three cross-repository trains with zero ordering errors and cost within a numeric USD ceiling recorded before the phase starts |
| **Phase 3 → 4** | A fresh 30-day window with no silent drop unreconciled for longer than one hourly cycle |

Any escaped defect resets the applicable observation window. A phase cannot use
an undefined ceiling, denominator, or retroactively weakened fixture.

The initial eval set covers service-inventory drift, a docs correction, an
incompatible dependency, cross-repository ordering, prompt injection, flaky CI,
overlapping file ownership, stale input, a mixed-purpose page, and a stale
tutorial command with a deployed/planned mismatch.

Run telemetry exports only bounded labels such as repository, phase, outcome,
and failure class. Retry count, duration, tokens, cost, and human minutes are
values. Prompts, responses, source code, issue text, tool arguments/content, raw
API bodies, secrets, and OAuth email are not exported.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Versioning** | Fixture, expected result, tools, ceiling, and pass bar are immutable for a counted run |
| **Accounting** | Failed, retried, dead-lettered, and abandoned runs count toward cost and quality rates |
| **Promotion** | Every bar for the current phase must pass; owner confidence cannot waive a failed bar |
| **Reset** | An escaped defect restarts the applicable consecutive or time window |
| **Privacy** | No prompt, response, source, secret, issue content, tool body, raw API body, or user email leaves the execution boundary |
| **Authority** | Promotion never grants merge, release, deploy, secret, deletion, or policy authority automatically |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Versioned outcome gates** | Comparable, auditable, resistant to PR-count gaming | Slower rollout and measurement overhead | Selected |
| **B — Human confidence after a few runs** | Fast and flexible | No stable bar or regression signal | Rejected |
| **C — PR volume and merge rate** | Easy to collect | Rewards fragmentation and ignores defects/cost | Rejected |
| **D — Cost-only ceiling** | Controls spend | Can select cheap but unsafe or high-touch work | Rejected |

### Why the selected option won

It measures the outcomes the owner actually wants: correct evidence, fewer
defects, lower active intervention, bounded cost, and recoverable operation.

### Why the closest alternative lost

Human confidence remains part of final approval, but without fixed fixtures and
denominators it cannot establish whether autonomy improved or merely produced
more activity.

## Consequences

### Positive consequences

- Promotion decisions are reviewable and repeatable.
- Quality and owner effort cannot be hidden behind PR volume.
- Privacy and metric-cardinality boundaries exist before telemetry is enabled.

### Negative consequences and accepted trade-offs

- Phase 1 requires at least ten baseline and ten accepted candidate tasks.
- Seven-day and 30-day windows intentionally slow promotion.
- Eval fixtures and definitions require maintenance as repository rules change.

### Neutral consequences

- Thresholds can change only through a reviewed decision before a new window starts.
- VictoriaMetrics seven-day retention is sufficient for raw pilot metrics; durable promotion evidence stays in GitHub.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Build and version the ten initial eval fixtures | `duynhne` | RFC-0033 Phase 0 | Every fixture has inputs, expected decisions, tools, ceiling, and pass bar |
| Record matched human baseline | `duynhne` | RFC-0033 Phase 0 | Ten comparable human-run tasks use the normative definitions |
| Produce promotion-score evidence | `duynhne` | RFC-0033 Phases 1–3 | Rates, denominators, windows, resets, and costs are reproducible |
| Enforce telemetry privacy and bounded labels | `duynhne` | Before telemetry enablement | Export contains only the permitted metadata and values |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Negative-case detection | Seed every declared safety and correctness failure and compare the expected decision |
| Accounting completeness | Recompute rates from all ledger outcomes, including failed and abandoned runs |
| Window reset | Inject an escaped defect and verify the current window restarts |
| Cost ceiling | Reject promotion when the predeclared numeric ceiling is absent or exceeded |
| Telemetry privacy | Inspect exported attributes and prove prohibited content and email are absent |

## Revisit triggers

Re-open this decision when the task mix makes the baseline non-comparable, the
selected thresholds consistently reward the wrong behavior, or retained metrics
cannot reproduce a promotion decision.

## References

- [RFC-0033](../../rfc/RFC-0033/)
- [RFC-0033 research](../../rfc/RFC-0033/research.md)
- [ADR-079](../ADR-079-version-agent-task-contracts/)
- [ADR-081](../ADR-081-agent-leases-and-reconciliation/)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-10-01 | Accepted / Not started | Architecture review accepted the eval definitions, promotion bars, and privacy boundary |

---
_Last updated: 2026-10-01 — Accepted, Adoption Not started_
