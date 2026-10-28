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

- Write in English, in **semantic (Conventional Commits) format** with a
  consistent scope: `type(scope): description`. The description is a
  lower-case imperative without a trailing period: `feat(databases): set
  PostgreSQL client names`.
- **Types:** `feat`, `fix`, `docs`, `chore`, `refactor`, `ci`, `perf`.
- **Scope** is one of the CHANGELOG components, lower-cased: `gitops`,
  `gateway`, `observability`, `databases`, `secrets`, `security`, `services`,
  `temporal`, `local-stack`, `docs`, `proposals`, `ci`. Include a scope
  whenever one fits; omit it only for a genuinely cross-cutting change
  (`type: description`).
- Keep the subject line, including the `type(scope):` prefix, to at most 72
  characters.
- Count the authored subject only; exclude a `(#PR)` suffix added by GitHub
  during squash merge. Do not add that suffix to ordinary commits.
- Separate the subject and body with a blank line. Keep the body concise,
  explaining what changed and why. Use paragraphs or bullets as appropriate.
  Wrap at 72 characters; leave URLs and indivisible tokens intact.
- Keep essential rationale in the message. Reference an owning ADR/RFC when
  relevant; detailed design belongs in that record. Include related document
  updates with the change they explain.
- Never mention external design references, visual-inspiration sites, or
  comparative platforms in commit messages, PR titles, or PR descriptions.
- Do not add `Fixes #123` or @-mentions.

### Author and co-author

Every commit is authored by **duynhne** with **duynebot** as co-author. The
local git identity on agent machines is often the bot, so set the author
explicitly on **every** commit you create — in this repo and in sibling repos:

```bash
git commit --author="duynhne <108656040+duynhne@users.noreply.github.com>" ...
```

Append exactly this trailer (after a blank line at the end of the message):

```text
Co-Authored-By: duynebot <bot@duynh.me>
```

- `Co-Authored-By: duynebot <bot@duynh.me>` is the **only** permitted
  attribution trailer. Forbid `Signed-off-by`, `Assisted-by`, `Generated-by`,
  and any tool-injected co-author (for example `Cursor
  <cursoragent@cursor.com>`) — strip those and keep only `duynebot`.
- GitHub squash-merge already credits duynhne as author, so setting `--author`
  matters most for commits pushed directly or carried on the PR branch.

## Branch names

Use a short kebab-case description after one of these prefixes:

| Prefix | Purpose |
|--------|---------|
| `feat/` | New capability |
| `fix/` | Bug fix |
| `chore/` | Maintenance or dependency updates |
| `docs/` | Documentation |
| `refactor/` | Restructuring without changing behavior |
| `perf/` | Performance improvement |
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
3. Check the subject, body and branch name against the rules above —
   including the `type(scope): description` format, the explicit
   `duynhne` author, and a single `Co-Authored-By: duynebot <bot@duynh.me>`
   trailer with no tool-injected co-author left behind. When reviewing,
   report concrete violations and provide a corrected message or name. Leave
   compliant messages unchanged unless rewriting was requested.

A request to draft or review messages does not authorize committing, pushing,
merging, or rewriting Git history. Perform those actions only within the
user's authorized task.

## Examples

Configuration change:

```text
feat(databases): set PostgreSQL client names

Set PGAPPNAME for services, workers and database jobs so query
telemetry can identify each client, as required by ADR-089.

Update the telemetry schema and dashboard pins together to keep
client-name queries compatible with the stored column.

Co-Authored-By: duynebot <bot@duynh.me>
```

Documentation change:

```text
docs(databases): clarify database access guidance

Separate current connection paths from the planned access contract
so operators can distinguish deployed behavior from rollout work.

Link the owning ADR instead of repeating its design decisions.

Co-Authored-By: duynebot <bot@duynh.me>
```
