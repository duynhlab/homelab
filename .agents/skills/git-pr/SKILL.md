---
name: git-pr
description: >-
  Write and review homelab branch names, commit messages, squash commit
  messages, and pull request titles and descriptions using the repository's
  contribution conventions. Use when naming a branch, committing, opening or
  updating a PR, or summarizing a branch for reviewers.
metadata:
  version: "2.0.0"
---

# Git commits and pull requests

This skill owns the text on the path to a merge: branch names, commit
messages, PR titles, PR descriptions, and squash messages. For the PR workflow
and Git/GitHub identity, follow
[AGENTS.md](../../../AGENTS.md#contribution-workflow). Validation gates live
in [platform-engineer](../platform-engineer/SKILL.md#verification-and-release).

## Writing style

Commit bodies and PR descriptions follow the ASD-STE100 sentence rules, without
its dictionary:

- Write in English, in the active voice, with one topic in each sentence.
- Keep descriptive sentences to 25 words and procedural sentences to 20 words.
- Keep necessary technical terms, proper nouns, and code identifiers.
- Write for a reviewer, not a changelog. The CHANGELOG is the release record.

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
- Closing keywords (`Closes #N`, `Fixes #N`) and @-mentions never go in a
  commit message. The PR description carries the issue link.

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

## Pull requests

The PR title becomes the squash subject, so it follows the commit subject
rules: `type(scope): description`, at most 72 characters, no `(#N)`.

Before you write, read the diff against the base, the commits, and the linked
issue or ADR. When you update a PR, read its current description first. Keep
text the owner wrote unless the request is to rewrite it.

Fill in [`.github/pull_request_template.md`](../../../.github/pull_request_template.md):

- **Summary.** Start with the issue line: `Closes #N`, `Part of
  #<sub-issue> (ADR-NNN)`, or one line that says there is no tracking issue.
  Do not open an issue only for a PR. Then write one paragraph of about 100
  words. Lead with the problem, need, or decision, then the change in
  behavior. Do not list files or narrate commits.
- **Tradeoffs.** State what was chosen over what, scope limits, follow-ups,
  and breaking or preserved behavior, only when they matter to review.
  "None" is a valid answer. A tradeoff the ADR did not settle also goes on
  its tracking issue
  ([`adr/README.md` § Working log](../../../docs/proposals/adr/README.md#working-log)).
- **Gate.** State only the checks that ran, as counts and outcomes. Name
  failures and skipped steps. Never paste a secret.

Write the description to a file in the scratchpad, then publish it with
`gh pr create --body-file <file>` or `gh pr edit --body-file <file>`. Before
you publish, confirm that the Summary leads with why the change is needed.

## Write or review

1. Inspect the actual diff for the requested change. When preparing a commit,
   use the staged diff; if nothing is staged, distinguish a draft based on the
   working diff from a message for a ready commit. For a squash message or a
   PR description, inspect the complete PR or branch diff against its base.
2. Describe the final change and its reason. For squash messages and PR
   descriptions, replace intermediate commit lists, repeated titles and
   abandoned approaches with one coherent explanation. Claim validation or
   compatibility only when supported by evidence.
3. Check the subject, body, PR title, PR description and branch name against
   the rules above — including the `type(scope): description` format, the
   explicit `duynhne` author, a single `Co-Authored-By: duynebot
   <bot@duynh.me>` trailer with no tool-injected co-author left behind, and
   no closing keyword in a commit. When reviewing, report concrete violations
   and provide corrected text. Leave compliant text unchanged unless
   rewriting was requested.

A request to draft or review messages does not authorize committing, pushing,
opening a PR, merging, or rewriting Git history. Perform those actions only
within the user's authorized task.

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

PR description, title `docs(observability): derive alert catalog counts from
deployed rules`:

```markdown
## Summary

Closes #1384

The alert catalog counted rule files, so it reported rules that Flux does
not apply. The domain table had also drifted from its sections. The catalog
now counts the rendered kustomizations, and each domain row matches its
sections. A script prints the counts and fails when a deployed alert has no
catalog row.

## Tradeoffs

The script checks names against rows, not rows against sections. The page
keeps the section-to-domain mapping, so there is no second source of truth.

## Gate

Script: 272 rules, exit 0. Script with one row removed: exit 1.
`make validate` passed. CI markdown-links passed.
```
