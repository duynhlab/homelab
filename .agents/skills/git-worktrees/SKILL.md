---
name: git-worktrees
description: >-
  Create, use, and clean up Git worktrees for homelab tasks without losing work
  or leaking stale checkouts, with Worktrunk (`wt`) as the preferred interface
  and plain Git as the fallback. Use when starting a task in a worktree,
  deleting a branch or worktree, or recovering a locked or orphaned checkout.
metadata:
  version: "1.1.0"
---

# Git worktrees

This skill owns worktree lifecycle and cleanup hygiene for homelab. For commit
messages, branch names and PR text, follow [git-pr](../git-pr/SKILL.md). For
the PR workflow and Git/GitHub identity, follow
[AGENTS.md](../../../AGENTS.md#contribution-workflow).

Every homelab worktree is a plain Git worktree. [Worktrunk](https://worktrunk.dev)
(`wt`) is the preferred interface on top of it: it addresses worktrees by
branch name, refuses to drop uncommitted work, and knows when a squash-merged
branch has landed. Each rule below gives the `wt` command and the plain-Git
fallback; both produce the same worktree shape.

## Tool detection

Check once per session:

```bash
command -v wt && wt --version
```

If `wt` is missing, use the plain-Git fallbacks. Never install it for the
owner; suggest `brew install worktrunk && wt config shell install` once and
move on. Confirm flags against the installed version with `wt <command> --help`
before relying on anything beyond the commands in this skill. The `wt` Claude
Code plugin, when installed, documents `wt` configuration, hooks and aliases in
its own `worktrunk` skill; this skill states only the homelab rules.

## One worktree per task

- One worktree per issue or task, one branch per task, one PR per task.
- Create off the latest `origin/main`, never from a dirty checkout. Worktrees
  live next to the repository as `../homelab.<branch>` with `/` replaced by `-`
  (Worktrunk's default path template; the template is user config and cannot
  be pinned in the repo):

  ```bash
  git fetch origin main
  wt switch -c <branch> --base origin/main              # → ../homelab.<branch-sanitized>
  wt switch -c -x claude <branch> --base origin/main -- "<task prompt>"   # same, with an agent in it

  # plain Git
  git worktree add -b <branch> ../homelab.<branch-sanitized> origin/main
  ```

  Keep the same directory shape in the fallback so `wt list` does not flag the
  checkout as off-template (`⚐`).

- Re-prompt a task that is already in progress (`wt switch <branch>`) instead
  of opening a second worktree for the same issue. Never work inside another
  task's checkout.

## Worktree isolation is not environment isolation

Worktrees isolate tracked files only. In homelab they share `.git`, the Podman
machine, the single Kind cluster, and local-stack's container names and ports.
Run `make up`, `make e2e`, or `docker compose up` from one worktree at a time;
`make validate` and `make docs-check` are safe to run in parallel worktrees.

## Never discard uncommitted work

Never remove a worktree that has uncommitted changes. `wt remove` refuses a
dirty worktree by default; do not answer that refusal with `wt remove -f`.
Commit the changes to the worktree's own branch first so they cannot be lost —
a throwaway local `wip(<scope>): …` commit is acceptable. It stays local;
squash it or amend it into the real commit before the PR (it is never pushed as
the final message).

## Prove a branch landed before deleting it

Homelab squash-merges every PR, so the merge commit's SHA differs from the
branch's. `git branch --merged main` is **not** evidence, and a branch can read
`ahead N` and still be fully merged — that is squash, not unmerged work. A file
diff against `origin/main` is not evidence either: once `main` has moved on the
same files (CHANGELOG does on every PR) the diff is non-empty for a branch that
landed in full. That check gave three false negatives on 2026-11-09 for PRs
#1515, #1516 and #1518.

Evidence that works:

- `wt list` shows `_` (same commit as `main`) or `⊂` (content integrated) in
  the Status column. `wt step prune --dry-run` lists the same set for a bulk
  preview.
- `wt remove <branch>` deletes the branch only when that check passes and
  refuses otherwise. Never answer the refusal with `-D`; find the PR and check
  what is missing.
- Plain Git: the branch's whole diff has the same patch-id as its squash
  commit on `main`, found by the `(#N)` suffix (checked against the three PRs
  above):

  ```bash
  git fetch origin main
  sq=$(git log origin/main --grep="(#<N>)" --format=%H -1)
  diff <(git diff $(git merge-base origin/main <branch>) <branch> | git patch-id --stable) \
       <(git show "$sq" --format= | git patch-id --stable)   # no output = landed
  ```

## Commands this repo never runs

- `wt merge`, `wt step push`, `wt step promote`: they merge or fast-forward
  `main` locally. Homelab merges only through a PR and `gh pr merge --squash`
  ([git-pr § Squash merge](../git-pr/SKILL.md#squash-merge)).
- `wt remove -f` (drops uncommitted work) and `wt remove -D` (deletes a branch
  that did not land).
- `wt step prune` without a `--dry-run` first and the owner's go-ahead on the
  listed set.
- `wt step commit`: it writes commit messages with an LLM; git-pr owns them.
- `--yes` on any command that removes something.

## Know the worktree class before removing

Run `wt list` (or `git worktree list`) first, then match the shape:

| Shape | Example | How to remove |
|-------|---------|---------------|
| Worktrunk worktree | `../homelab.<branch>` | `wt remove <branch>` |
| Legacy sibling worktree (`⚐` in `wt list`) | `../homelab-<task>` | `wt remove <path>` — paths are accepted |
| Legacy agent worktree, before the `wt` Claude plugin | `.claude/worktrees/*` | `wt remove <path>` or `git worktree remove <path>` |
| Record whose directory is gone | — | `git worktree prune` |

With the `wt` Claude Code plugin installed (owner's machine since 2026-11-09),
Claude Code's own `isolation: worktree` checkouts go through `wt switch` and
land at `../homelab.<branch>` like every other worktree; `.claude/worktrees/`
holds only older ones.

## Stale lock, owner process gone

Re-run the clean-tree and landed checks **first**, then unlock, then remove.
Unlocking before the checks defeats them:

```bash
# confirm clean + landed, then:
git worktree unlock <path>
wt remove <path>            # or: git worktree remove <path>
```

## Verify the cleanup

After a cleanup pass, `git fsck` is clean and `wt list` (or
`git worktree list`) shows only real checkouts. `git worktree prune` drops
records whose directories are gone.

## Project configuration

Homelab has no `.config/wt.toml`. No hook earns its place yet: `make validate`
stays a manual gate, and local-stack cannot run per worktree. Add one only
with a reason in the PR, and never a hook that removes or deploys.
