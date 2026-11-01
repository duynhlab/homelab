# Track platform work

<!-- Private Project requires organization access; verified through authenticated gh. -->
<!-- markdown-link-check-disable-next-line -->
Use [Platform work](https://github.com/orgs/duynhlab/projects/1) to find the next task,
remaining verification, and deferred work across duynhlab.

| Quick facts | |
|---|---|
| **Page type** | How-to |
| **Audience** | Platform owner, contributors, and agents |
| **Prerequisites** | Repository access; Projects access for board updates |
| **Environment** | GitHub organization `duynhlab`; no cluster mutation |
| **Changes state** | Issues, relationships, labels, and Project fields |
| **Evidence context** | Project and issue inventory inspected 2026-11-01; see linked trackers for current work |
| **This page owns** | Work intake, selection, progress, and completion |
| **Not this page** | [Design approval](../proposals/README.md), [release gates](../../AGENTS.md#build-test-deploy), or [PR text](../../.agents/skills/git-pr/SKILL.md) |

## Choose the source of truth

| Question | Source |
|---|---|
| What design is proposed or accepted? | RFC / ADR decision status |
| What remains to deliver or verify? | Issue and native sub-issues |
| What should start next, or is waiting? | Project Status and priority labels |
| What changed and which checks passed? | PR and gate evidence |
| Which decision obligations are adopted? | ADR Adoption and linked completion evidence |

An accepted design is not a scheduling commitment. A merged PR is not proof of a
runtime gate. Historical audit reports remain evidence snapshots, not live queues.

## Capture and triage

1. Search open and closed issues, PRs, and the owning RFC/ADR before creating work.
2. Reuse an existing issue when the desired outcome is the same. Link a regression
   to prior evidence without rewriting the historical record.
3. Use the issue form for the outcome. Set native type, a primary `area/*` label,
   scope, acceptance criteria, verification, and a concrete next action.
4. Add the issue to Platform work with **Needs triage**. Assign the accountable
   owner when selecting the work. A repository named in prose is not an assignee.
5. During triage, record the next action and choose Backlog, Ready, or Waiting.
   Select one priority label. Keep uncertain historical findings in Needs triage
   until current source and evidence have been checked.

Small self-contained PRs can stand alone. A follow-up that survives the current PR
needs an issue. Do not create an issue solely to satisfy a PR template.

### Group work by outcome

Use a parent issue labelled `epic` for a bounded initiative and native sub-issues
for independently verifiable tasks. Prefer two levels. Use an existing ADR tracker
when it already owns that outcome; retain its `adr` type.

Several ADRs can share an initiative. Each task links the decisions it implements.
Use a dedicated ADR tracker only when that decision has independent delivery
obligations. A small task does not need an empty parent or one issue per checkbox.

Keep platform-wide audit acceptance in homelab. Put application implementation
in its owning repository and link its issue/PR to the platform acceptance task.
Reuse an existing cross-repository issue instead of copying it.

Use native blocked-by relationships for issue dependencies. For hardware, external
upstream work, or an owner decision, name the blocker and the event that resumes
work. A link alone does not establish a native relationship.

## Select and move work

| Status | Entry condition | Next action |
|---|---|---|
| Needs triage | Newly captured or evidence is uncertain | Confirm scope, owner, and current evidence |
| Backlog | Valid retained work, not selected | Review when capacity or need changes |
| Ready | Scope and acceptance clear; no unmet prerequisite | Assign and start |
| Analysis | Research, sizing, or comparison actively underway | Gather evidence and prepare a concrete recommendation |
| In progress | Implementation, operations, or procurement actively underway | Keep the next action current |
| Review | A concrete proposal or change awaits owner review | Review the design, purchase recommendation, or PR |
| Verification | Implementation exists; required evidence remains | Run the named gate or locate valid evidence |
| Waiting | Named blocker or revisit trigger | Revisit when that condition changes |
| Done | Issue closed with a recorded disposition | Read closure reason and evidence |

Keep at most two leaf tasks across Analysis and In progress per accountable owner.
Parent initiatives summarize child progress and do not consume this limit. Owner instructions can
explicitly select a different work limit.

Use Analysis for active investigation; Needs triage only establishes scope and
evidence quality. Skip stages that do not apply to the task. A hardware-selection
task can move from Analysis to Review and close after the owner selects a qualified
option. Purchasing and commissioning remain separate outcomes.

Use one `priority/*` label after triage: `critical` for immediate incidents or
release blockers, `high` for concrete impact or prerequisites, `normal` for planned
work, and `low` for optional improvements. Priority is not duplicated in a Project
field. Proposed designs can have high priority while remaining Waiting.

Milestones identify a real release in the owning repository. Leave a milestone
unset until that release is selected; use the organization Project across repos.

### Labels

The catalog is [`.github/labels.yaml`](../../.github/labels.yaml). Label sync retains
automation-owned labels. Change a label used by tooling only after checking its
consumers.

| Dimension | Use |
|---|---|
| Native type | `Bug`, `Task`, `Feature`; `adr` for existing or independent ADR trackers |
| Initiative | `epic` plus native sub-issues |
| Domain | One primary `area/*`; additional domains only when relevant |
| Priority | At most one `priority/*` |
| Waiting reason | `blocked/upstream`, `blocked/decision`, `blocked/hardware`, or `blocked/requires-rfc` |
| Additional properties | `regression`, `dependencies`, `documentation`, `help wanted`, `good first issue` |
| PR tooling | Existing `size/*`, `stop-updating`, and bot-owned labels |

Use `area/observability` for signal work and `documentation` for documentation work.
Legacy `area/monitoring`, `area/docs`, `umbrella-issue`, `bug`, and `task` labels remain
available for existing consumers; avoid adding redundant aliases to new issues.
`area/rfc` and `area/adr` identify design artifacts, not the implementation domain.

Project Status owns execution state. Do not maintain separate `triage`, `groomed`,
or `in-progress` labels. Existing PR `hold` labels remain valid release controls;
for issue scheduling, use Waiting with the blocker written beside its next action.

## Use the views

| View | Selection |
|---|---|
| Kanban board | First view; all Project items grouped by Status, including initiatives and Done |
| Work items | Complete Project inventory in a table |
| Inbox | Open work with Status Needs triage |
| Roadmap | Open parent initiatives labelled epic |
| Ready | Ready leaf work |
| Doing | Analysis, In progress, and Review leaf work |
| Verification | Leaf work missing completion evidence |
| Waiting | Work with an explicit blocker or trigger |
| Recently completed | Closed items from the last 30 days, including their closure reason |

The Project retains its default private visibility. Repository issues keep their
own visibility. Adding a public issue does not publish the Project.

## Complete and resume work

Before closing an issue, link the implementation and verify every acceptance
criterion. If code landed but the runtime gate did not run, use Verification and
name the exact gate. Use `Part of` in the PR until it completes the issue.

Close abandoned work as not planned with a reason and, when applicable, a successor
or revisit trigger. Done means closed; it does not change an ADR to Complete.
Update ADR Adoption only when that decision's obligations have evidence. Update
RFC implementation status when its accepted scope has been delivered.

Before ending an agent session, record progress, evidence, remaining work, and the
next action on the existing issue. Update Project Status. Do not copy the live
list of open sub-issues into RFC/ADR prose; link the tracker instead.

## Review the queue

Review Inbox, Waiting, Verification, and unassigned selected work weekly. Check
that new issues were added to the Project and that every deferred commitment has
an issue or an explicit revisit trigger. Reconcile historical audit holds with
actual PR state before creating new work.

Built-in Project automation adds sub-issues and reflects closed issues. PR linking
and merging do not complete an issue. There is no inactivity auto-close. Issue forms select `duynhlab/1` for authors with Project write access. CLI-created
issues must explicitly select the Project; check membership after creation.
External contributors without Project write access need maintainer triage. No
repository auto-add job is configured.

Compare proposal index entries with opening record metadata before pushing
metadata changes. Historical ADRs without an Adoption field retain the index as
their source. Resolve differences against completion evidence; metadata alignment
does not certify runtime adoption.

## If something goes wrong

| Symptom | Action |
|---|---|
| A task is absent from every view | Check Project membership and Work items; set Status after confirming the issue |
| A merged PR left a task open | Read its acceptance criteria; preserve Verification when runtime evidence is missing |
| An index disagrees with its record | Check the original completion evidence; align the index without inventing new adoption |
| A waiting task has no next action | Name the blocker and observable resume trigger before leaving it Waiting |
| An old audit still lists merged PRs | Preserve the audit date; replace its live queue with links to current work items |

## References

- [GitHub Projects](https://docs.github.com/en/issues/planning-and-tracking-with-projects/learning-about-projects/about-projects)
- [Native sub-issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues)
- [Issue form Projects field](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms)
- [Project filters](https://docs.github.com/en/issues/planning-and-tracking-with-projects/customizing-views-in-your-project/filtering-projects)
