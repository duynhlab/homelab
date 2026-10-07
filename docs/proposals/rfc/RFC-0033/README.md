# RFC-0033 Claude-native autonomous engineering organization

| Status | Scope | Research | Created | Last updated |
|--------|-------|----------|---------|--------------|
| Accepted | platform-wide | [./research.md](./research.md) — gate passed 2026-09-28 | 2026-09-28 | 2026-10-01 |

## Prerequisites

- [x] [`research.md`](./research.md) merged; [research review gate](./research.md#research-review-gate) passed
- [x] Context7 audit complete; exceptions and official-document checks are recorded in the research
- [x] Owner approved **ready for RFC** on 2026-09-28
- [x] This RFC summarizes the target and links the mechanism deep dive instead of repeating it
- [x] Architecture review accepted the five resulting ADRs on 2026-10-01; `docs/api/` is N/A until a later implementation changes an application contract

## Summary

Build a human-gated engineering control loop around the existing Homelab repositories.
GitHub remains the durable work ledger, repository instructions and contracts remain the
source of truth, and isolated Claude workers prepare narrow draft changes with
independently reproducible evidence. Human owners keep merge, release, deployment,
policy-exception, and credential authority.

The initial candidate uses bounded interactive or GitHub Actions jobs. Claude Code
routines may be qualified later as trigger surfaces, but they are not a durable queue,
security boundary, or liveness monitor. A custom Agent SDK controller remains deferred
until measured gaps justify its operational cost. No runtime component is installed by
this RFC.

## Motivation

Homelab already coordinates ten Go services, two web clients, shared packages, reusable
CI, GitOps, release evidence, and a large technical documentation corpus. The platform
owner still performs most task decomposition, context routing, polling, retry, and proof
assembly manually. More parallel agent sessions amplify that coordination load unless
the work contract, authority boundaries, evidence, and recovery state become durable.

The research establishes the useful pattern behind the xAI material without copying its
unverified hierarchy or optimizing for PR volume. See
[`research.md`](./research.md#source-triage-claim-evidence-and-lesson).

### Goals

- Reconstruct every delegated task from versioned repository truth and GitHub state,
  without relying on hidden chat memory.
- Keep one worker inside one repository and isolated worktree unless a parent change
  train explicitly coordinates several repositories.
- Require deterministic checks and independently reproducible evidence before human
  review.
- Reduce owner routing and polling time without increasing escaped defects, rework, or
  cost per accepted change.
- Treat `docs/` as an executable learning and knowledge plane with clear reader
  contracts from first success through platform ownership.
- Earn unattended triggers through measured phases while preserving human merge and
  deployment authority.

### Non-Goals

- Reproduce a fixed 15-agent organization or nested manager hierarchy.
- Install an always-running controller, Claude routine, GitHub App, workflow, hook, or
  agent definition in this RFC.
- Let an agent approve or merge pull requests, deploy, reconcile Flux, rotate secrets,
  delete data, loosen policy, or approve its own guardrail changes.
- Replace GitHub, CI, Flux, `AGENTS.md`, project skills, `docs/api/`, RFCs, or ADRs with
  agent memory.
- Move application source code into Homelab or make PR count a productivity metric.

## Proposal

Adopt a phased, flat control plane with one coordinator, four specialist lanes, a
trusted publisher, and disposable workers:

| Role | Responsibility | Initial authority |
|------|----------------|-------------------|
| Coordinator | Normalize goals, build the task graph, lease work, monitor bounded retries, and assemble evidence | Read truth, update qualified ledger fields, request work; no merge or deploy |
| Contract and architecture | Check API ownership, RFC/ADR status, compatibility, and cross-repository order | Read and report constraints |
| Delivery | Select repository-local procedures and launch a scoped worker | Launch only within the validated task envelope |
| Assurance and agent ops | Re-run proof from independent context, classify failures, and propose guardrail changes | Verdict and request-changes only |
| Documentation Steward | Protect technical truth, reader contracts, learning paths, examples, navigation, and accessibility | Draft and review; technical owner approves truth |
| Trusted publisher | Validate the complete patch against the authorized lease before publishing | Human-operated in Phases 0–1; a later qualified GitHub App is limited to the assigned repository, branch, and paths |
| Worker | Implement one leased task in one repository/worktree | Read checkout and produce a local patch; no GitHub write token |

The topology stays flat. The coordinator may launch workers; workers cannot launch more
agents. Runtime depth, concurrency, retry, turn, time, and spend limits are explicit and
fail closed.

### User stories

- As the platform owner, I can submit one bounded outcome and review a task graph plus
  reproducible evidence instead of manually polling every session.
- As a service owner, I can see which contract, base SHA, repository rule, and release
  gate authorized an agent-authored change.
- As a reviewer, I can distinguish deterministic proof, model judgment, and facts that
  still require a domain-owner verdict.
- As a new engineer, I can follow a safe learning path; as an experienced engineer, I
  can jump directly to exact contracts, failure mechanics, and decision evidence.
- As an operator, I can tell whether the automation is healthy, paused, stale, or
  dead-lettered without opening a Claude conversation.

### Alternatives

| Alternative | Benefit | Cost | RFC position |
|-------------|---------|------|--------------|
| Bounded jobs + GitHub ledger + optional qualified routines | Smallest new operational surface; reuses existing truth and CI | Requires reconstruction on every run; routine events may be dropped and routine identity is the owner's | **Selected** |
| Thin Agent SDK coordinator + GitHub ledger | Explicit queueing, budgets, recovery, and identity integration | New production service, persistence, secrets, telemetry, upgrades, and on-call ownership | Defer until Phase 4 evidence |

## Other solutions considered

| Option | Shape | Why not chosen |
|--------|-------|----------------|
| Interactive agent teams only | One long-lived collaborative Claude session | Experimental and session-bound; no durable recovery or unattended trigger model |
| Human-started sessions with better prompts | Continue today's workflow with stronger prompts | Leaves the owner as scheduler, router, and retry loop; serves only as the evaluation baseline |
| Adopt Grok Bot directly | Use persistent external bots and routines | Shared per-user security boundary and a control model not yet qualified against Homelab's GitOps and release obligations |
| Build an SDK controller immediately | Start with a bespoke always-on service | Commits to the largest operational surface before routine and bounded-job gaps are measured |

## Decision outcome

**Chosen option:** bounded jobs + GitHub ledger + optional qualified routines

**Rationale:** bounded jobs plus the GitHub ledger provide the lowest-risk path to test
task contracts, isolated work, independent proof, and recovery using systems Homelab
already operates. Phases 0–1 keep publishing human-operated, and routines remain optional
trigger surfaces until qualified. The Agent SDK path remains the runner-up when measured
evidence shows that configuration cannot close a durability, identity, or concurrency
gap.

## Architecture & Diagrams

This sequence answers one question: in the **planned** control loop, which boundary may
turn a task into a repository write, and who may approve it?

```mermaid
sequenceDiagram
    actor Owner as Human owner
    participant Ledger as GitHub ledger
    participant Coord as Planned coordinator
    participant Worker as Planned isolated worker
    participant Publish as Planned publishing boundary
    participant CI as CI and deterministic gates
    participant Verify as Planned independent verifier

    Owner->>Ledger: Authorize exact revision and checksum
    Coord->>Ledger: Read authorized task revision and immutable base SHA
    Coord->>Worker: Lease one repository and allowed paths
    Worker->>Publish: Return patch and evidence without a write token
    Publish->>Publish: Validate full diff, lease, base SHA, and branch
    Publish->>Ledger: Push planned branch and draft PR
    Ledger->>CI: Run repository-owned gates
    CI-->>Ledger: Publish immutable results
    Coord->>Verify: Request clean-context evidence review
    Verify->>Ledger: Publish verdict and reproduced evidence
    Coord-->>Owner: Assemble ready, blocked, or dead-letter packet
    Owner->>Ledger: Approve and merge, or request changes
```

The sequence is a target, not deployed reality. GitHub and current CI exist today; the
coordinator, worker definitions, verifier, and task contract are planned.

## Design Details

### Durable task and proof contract

Homelab owns a versioned JSON Schema for the task payload. Required fields are the goal,
repository and allowed paths, immutable base SHA, inputs, acceptance proof, forbidden
actions, risk, retry/time/turn/cost budgets, escalation conditions, and expected output.

A GitHub issue form is only an untrusted human entry point because GitHub renders and
allows edits to submitted Markdown; its YAML field IDs are not assumed to survive as a
documented machine interface. Phase 0 must fixture the exact rendered body, pin the form
template version and checksum, and fail closed on an unknown heading or structural edit.
If that representation cannot be qualified, intake moves to a structured surface.

A trusted normalizer converts qualified input into schema-versioned JSON and publishes a
candidate revision and checksum. Syntax validity is not authority. Before lease, an
allowlisted owner must create a separate authorization record binding their identity to
that exact task revision, payload checksum, immutable base SHA, and approval timestamp.
Editing the body or publishing another candidate never mutates authorized work in place;
it creates a new revision that requires new approval. The normalizer identity is separate
from workers, which cannot write or forge task, authorization, or lease records.

Every task carries these universal gates:

1. schema validity;
2. immutable-base freshness and clean worker state;
3. complete, reproducible evidence;
4. repository-specific gates discovered from the target repository's `AGENTS.md` and
   referenced rather than copied into the coordinator.

A missing, contradictory, or ambiguous rule blocks the task.

### Execution and identity

Phases 0–2 use human-started Claude sessions or bounded GitHub Actions jobs. Each worker
uses one repository and isolated worktree. The worker and verifier have separate context;
that is a quality boundary, not an identity boundary. Workers receive a read-only checkout
and no GitHub write token. They return a patch plus evidence. In Phases 0–1 a human
reviews that complete output, pushes the branch, and opens the draft pull request.

Unattended repository writes require a dedicated GitHub App installed only on the target
repository. Installation tokens are short-lived and available only to the publisher,
which validates the complete diff against the authorized lease, allowed and forbidden
paths, base SHA, and destination branch before writing. GitHub's `contents:write` is a
repository permission, not a task-specific path boundary; the publisher supplies that
missing enforcement outside the prompt.

The candidate permission envelope is contents, pull requests, and issues for writes;
checks and commit statuses are read-only. Actions is read-only only when an accepted
evidence flow must retrieve workflow artifacts. Administration and workflow-definition
writes are excluded. The identity ADR must prove an endpoint-by-endpoint permission
matrix and negative tests before any unattended write path is enabled.

Claude Code routines act through the owner's linked identity and belong to an individual
account. Until an execution path can route writes through the qualified App, routines
remain read-only qualification or trigger surfaces; they do not receive unattended
repository-write authority.

### Trigger, ledger, and recovery semantics

GitHub stores desired state, task revisions, authorizations, leases, idempotency keys,
retry history, evidence, outcomes, and dead-letter state. A trigger does not own that
state. Comments provide an audit trail, not compare-and-swap semantics.

A single trusted dispatcher serializes transitions for each task revision, backed by a
task-and-revision-keyed GitHub Actions concurrency group. The authoritative lifecycle is
`ready → leased → verifying → ready-for-human`, with terminal or recovery transitions to
`blocked`, `expired`, or `dead-letter`. A lease binds the authorized revision and checksum,
base SHA, holder/run ID, acquisition time, expiry, and renewal time. Only the dispatcher
may acquire or renew it. A newer payload revision invalidates eligibility for the old
revision; an active old lease stops at its next boundary and never changes scope in place.

Phase 3 may add supported routine schedules or GitHub events only after drills prove:

- duplicate delivery is idempotent;
- dropped or rejected events are backfilled;
- green routine infrastructure is not confused with task success;
- usage caps, stale inputs, prompt injection, and dependency outages fail closed;
- retries stop at declared budgets;
- a stale lease becomes visible and recoverable.

The trusted dispatcher writes a heartbeat only after one semantic reconciliation scan
completes. It includes a monotonically advancing ledger-event watermark and completion
timestamp; the minimum expected cadence is one hour. A separate scheduled GitHub Action
checks watermark age and opens or updates one incident issue when stale. Recovery resumes
from the last watermark. The check is outside Claude's failure domain, but it still shares
GitHub, workflow, repository-permission, and incident-issue failure domains. A total GitHub
outage or disabled workflow is therefore undetectable inside this best-effort, no-SLO
pilot. An external alert path requires a separate operating decision; the routine cannot
certify its own liveness.

### Change trains and release proof

Cross-repository work uses one parent issue and an ordered dependency graph. Contract,
producer, consumer, release, and delivery changes advance only after their prerequisites
are recorded in GitHub.

The compose audit may be exercised on sibling PR worktrees for early integration proof.
The normative repository rule remains: run the full API, browser, and telemetry audit
against the exact merged commit SHAs before tagging affected service, `pkg`, gateway,
Compose, or SPA changes. Tag and pin only that passing set, then run the Kind gate once
as the final pass.

### Documentation knowledge plane

The Documentation Steward classifies every new or materially changed page as tutorial,
how-to, reference, or explanation. Four planned templates under `docs/_templates/` own
those reader contracts. The existing `platform-engineer` skill will point to the
templates; a separate documentation skill is not introduced.

Executable examples use an HTML marker immediately before a fenced block:

```markdown
<!-- example-policy: ci-safe -->
```

Allowed values are `ci-safe`, `ephemeral`, and `review-only`; absence means
`review-only`. Classification applies to the entire block. Destructive, production,
secret-rotation, Flux-reconciliation, and real-data mutations never execute from docs
CI.

The first capability-map pilot is `docs/observability/`, linked to its canonical visual
views under `docs/architecture/observability/`. Broken links, missing index entries, and
diagram rendering form the deterministic canary. A semantic count or deployed/planned
correction additionally needs a canonical source, reproducible command or query, and
independent domain-owner verdict.

### Promotion metrics

Definitions and starting bars are normative for the pilot:

- **First-pass gate:** every predeclared deterministic check passes on the first pushed
  candidate without a worker follow-up.
- **Rework:** a human requests a correctness, scope, security, or contract change;
  formatting-only edits do not count.
- **Escaped defect:** a merged change needs a corrective PR or revert because an
  acceptance criterion, contract, or safety boundary was wrong.
- **Human intervention:** active routing and review minutes, excluding CI wait time.
- **Accepted candidate:** a human-merged Phase 1 PR whose seven-day observation window
  completed without an escaped defect.
- **Matched baseline:** at least ten human-run tasks in the same repository, task class,
  and risk bucket, measured with the same active-minute definition.
- **Reconciliation cycle:** one completed hourly scan of all ledger events after the
  previous monotonic watermark.

Phase 0 requires all ten versioned evals to pass twice; no more than 10% of all seeded
negative assertions across those 20 runs may be incorrectly reported as findings.
Phase 1 requires ten consecutive accepted candidates, at least 80% first-pass gates, at
most 20% rework, zero escaped defects, and median human minutes at most half the matched
baseline. Phase 2 requires three cross-repository trains without ordering errors and
within a numeric USD ceiling recorded in the versioned eval configuration before the
phase starts. Phase 3 requires a fresh continuous 30-day window with no silent drop left
unreconciled for longer than one hourly cycle. An escaped defect resets the applicable
observation window; promotion never relies on an undefined ceiling or denominator.

### Enablement, disablement, and drawbacks

No component is enabled by merging this RFC. Each phase requires reviewed implementation
changes and starts disabled. Pausing triggers, revoking the App installation, or removing
the workflow stops new work; active leases move to blocked or dead-letter state and are
not silently reassigned.

Operators determine use from GitHub task state, checks, heartbeat age, dead-letter
issues, and minimal run metrics. The design costs additional schemas, eval fixtures,
review discipline, GitHub automation, token spend, and owner attention. Fresh-session
reconstruction adds latency. Human merge gates deliberately cap throughput. The design
does not promise continuous availability or eliminate model judgment.

## Security considerations

- Retrieved issues, comments, websites, logs, and routine payloads are untrusted data,
  not instructions or approval.
- Repository scope, branch protection, App permissions, owner authorization, and the
  publisher's full-diff path validation are enforced outside prompts.
- Worker isolation prevents file collisions but does not prevent logical contract
  conflicts; immutable SHAs and the dependency graph remain mandatory.
- Workers cannot spawn agents. Depth is pinned to one, the `Agent` tool is absent from
  workers, and concurrency plus spend are capped.
- Prompts, responses, tool arguments, tool content, raw API bodies, source code, secrets,
  and issue text are not exported as telemetry. OAuth `user.email` is dropped.
- Guardrail, hook, permission, schema, and CI changes require normal human-reviewed PRs;
  an agent cannot approve its own control-plane changes.
- Merge, release, deploy, Flux reconciliation, secret rotation, deletion, and policy
  exceptions remain human-only.

## Observability & SLO impact

The pilot has no availability SLO and is owned by the platform owner on a best-effort
basis. Failure defaults to pause and record.

The GitHub ledger retains the task ID and per-task evidence. VictoriaMetrics receives
only bounded labels such as repository, phase, outcome, and failure class; retry count,
duration, tokens, cost, and human-intervention minutes are values, never labels. Metrics
use the existing seven-day retention. Detailed agent-run logs are not exported; GitHub
retains the durable task and evidence history under normal repository lifecycle rules.

Before Phase 3, add a heartbeat-age alert, queue-age view, dead-letter count, budget
exhaustion signal, and promotion-score report. A stronger response target requires a
separate operating decision and on-call owner.

## Rollout & rollback

| Phase | Capability | Exit bar | Authority ceiling |
|-------|------------|----------|-------------------|
| 0 — eval harness | Read-only audits, task/proof schema, normalizer fixture, human baseline | Ten evals pass twice and false-positive bar holds | Read-only |
| 1 — one-repo canary | One worker and verifier on Homelab docs | Ten observed candidates meet quality, rework, defect, and human-time bars | Draft PR; human merge |
| 2 — change trains | Parent/child ledger and dependency sequencing | Three compatible trains with no ordering error | Draft PRs; human merge/deploy |
| 3 — triggers | Qualified routines, heartbeat, budgets, reconciliation, and dead letter | Event, cap, stale-input, injection, false-green, and outage drills pass for 30 days | Same human gates; no auto-merge |
| 4 — controller decision | Compare measured Option B gaps with an SDK controller | Separate RFC/ADR identifies the missing guarantee and operator | Undecided |

Rollback is phase-local: stop triggers, revoke automation credentials, mark leases
blocked, and continue from GitHub with human-run sessions. Rollback never rewrites task
or evidence history. A later phase cannot inherit broader authority automatically.

## Testing / verification

- Version every eval fixture, expected decision, allowed-tool set, cost ceiling, and
  machine-checkable pass bar.
- Seed true and false documentation drift, an incompatible dependency, a cross-repo
  ordering error, prompt injection, flaky CI, overlapping file ownership, stale input,
  a mixed-purpose page, and a stale tutorial command.
- Fixture the rendered Issue Form Markdown and reject template/checksum or structural
  drift; validate task revisions against the checked-in JSON Schema.
- Reject malformed, stale, unauthorized, or checksum-mismatched revisions before lease;
  prove that workers cannot create task, authorization, lease, or publisher records.
- Race duplicate triggers against the task-keyed serializer, expire and renew a lease,
  and publish a new payload revision while an old lease is active.
- Prove the publisher rejects an out-of-scope path, forbidden control-plane file, stale
  base SHA, wrong branch, incomplete diff, and unapproved revision before using a token.
- Prove worker and verifier start from clean context and reproduce the declared gates.
- Drill duplicate, dropped, rejected, and false-green routine events plus a disabled
  GitHub connection and stale heartbeat.
- Render every changed Mermaid diagram, validate links and fences, and run the target
  repository's own checks.
- Record cost, retries, evidence completeness, human-active minutes, defects, and the
  seven-day observation result for each counted Phase 1 candidate.

## Resulting decisions

Architecture review accepted these independent decisions on 2026-10-01. Adoption remains
`Not started`; these records authorize Phase 0 design constraints, not runtime installation:

| Decision | ADR | Status |
|----------|-----|--------|
| Versioned task/proof contract and GitHub ledger representation | [ADR-079](../../adr/ADR-079-version-agent-task-contracts/) | Accepted / Not started |
| Tokenless workers, human-first publishing, and the future GitHub App boundary | [ADR-080](../../adr/ADR-080-tokenless-agent-workers/) | Accepted / Not started |
| Trigger, lease, reconciliation, heartbeat, and dead-letter semantics | [ADR-081](../../adr/ADR-081-agent-leases-and-reconciliation/) | Accepted / Not started |
| Evaluation metrics and trust-ladder promotion gates | [ADR-082](../../adr/ADR-082-agent-evaluation-gates/) | Accepted / Not started |
| Documentation Steward contracts and executable-example policy | [ADR-083](../../adr/ADR-083-documentation-steward/) | Accepted / Not started |

## Implementation History

- **2026-10-01 — Accepted:** architecture review selected bounded jobs plus the
  GitHub ledger, accepted ADR-079 through ADR-083 at Adoption `Not started`, and
  kept publishing human-operated for Phases 0–1. No runtime, workflow, schema,
  App, routine, hook, or agent definition is installed. Phase 0 is eligible.
- **2026-09-28 — Provisional:** research gate passed and owner approved RFC authoring.
  No runtime, workflow, schema, App, routine, hook, or agent definition is installed.

## Related

- [Research and source audit](./research.md)
- [Repository proposal process](../../README.md)
- [Platform-engineer operating procedure](../../../../.agents/skills/platform-engineer/SKILL.md)
- [Local-stack E2E release audit](../../../../local-stack/docs/e2e-audit.md)
- [Claude Code routines](https://code.claude.com/docs/en/routines)
- [GitHub issue form syntax](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms)
- [GitHub App permissions](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app)
