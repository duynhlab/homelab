---
name: git-commits
description: >-
  Write and review homelab commit messages, squash commit messages,
  and branch names using the repository's contribution conventions.
---

# Git commits

This skill owns commit-message and branch-name conventions for homelab.
For the PR workflow and Git/GitHub identity, follow
[AGENTS.md](../../../AGENTS.md#contribution-workflow). Validation gates live
in [platform-engineer](../platform-engineer/SKILL.md#verification-and-release).

## Commit messages

- Write in English. Use a capitalised imperative subject of at most 50
  characters, without a trailing period: `Set PostgreSQL client names`.
  Use plain subjects without Conventional Commits or Databasus prefixes.
- Count the authored subject only; exclude a `(#PR)` suffix added by GitHub
  during squash merge. Do not add that suffix to ordinary commits.
- Separate the subject and body with a blank line. Keep the body concise,
  explaining what changed and why. Use paragraphs or bullets as appropriate.
  Wrap at 72 characters; leave URLs and indivisible tokens intact.
- Keep essential rationale in the message. Reference an owning ADR/RFC when
  relevant; detailed design belongs in that record. Include related document
  updates with the change they explain.
- Do not include attribution trailers (`Co-authored-by`, `Signed-off-by`,
  `Assisted-by`, `Generated-by`, etc.), `Fixes #123`, or @-mentions.

## Branch names

Use a short kebab-case description after one of these prefixes:

| Prefix | Purpose |
|--------|---------|
| `feat/` | New capability |
| `fix/` | Bug fix |
| `chore/` | Maintenance or dependency updates |
| `docs/` | Documentation |
| `refactor/` | Restructuring without changing behavior |
| `ci/` | CI workflows and automation |

Examples: `feat/postgres-client-names`, `docs/database-access-guide`.

## Write or review

1. Inspect the actual diff for the requested change. When preparing a commit,
   use the staged diff; if nothing is staged, distinguish a draft based on the
   working diff from a message for a ready commit. For a squash message,
   inspect the complete PR or branch diff against its base.
2. Describe the final change and its reason. For squash messages, replace
   intermediate commit lists, repeated titles and abandoned approaches with
   one coherent explanation. Claim validation or compatibility only when
   supported by evidence.
3. Check the subject, body and branch name against the rules above. When
   reviewing, report concrete violations and provide a corrected message or
   name. Leave compliant messages unchanged unless rewriting was requested.

A request to draft or review messages does not authorize committing, pushing,
merging, or rewriting Git history. Perform those actions only within the
user's authorized task.

## Examples

Configuration change:

```text
Set PostgreSQL client names

Set PGAPPNAME for services, workers and database jobs so query
telemetry can identify each client, as required by ADR-089.

Update the telemetry schema and dashboard pins together to keep
client-name queries compatible with the stored column.
```

Documentation change:

```text
Clarify database access guidance

Separate current connection paths from the planned access contract
so operators can distinguish deployed behavior from rollout work.

Link the owning ADR instead of repeating its design decisions.
```
