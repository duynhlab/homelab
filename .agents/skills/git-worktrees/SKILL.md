---
name: git-worktrees
description: >-
  Create, use, and clean up Git worktrees for homelab tasks without losing work
  or leaking stale checkouts. Use when starting a task in a worktree, deleting a
  branch or worktree, or recovering a locked or orphaned checkout.
---

# Git worktrees

This skill owns worktree lifecycle and cleanup hygiene for homelab. For commit
messages and branch names, follow [git-commits](../git-commits/SKILL.md). For
the PR workflow and Git/GitHub identity, follow
[AGENTS.md](../../../AGENTS.md#contribution-workflow).

Homelab has **no desk manager or worktree wrapper** — every worktree is a plain
Git worktree, so `git worktree add`, `git worktree remove` and
`git worktree prune` are always the right tools.

## One worktree per task

- One worktree per issue or task, one branch per task, one PR per task.
- Create off the latest `origin/main`, never from a dirty checkout:

  ```bash
  git fetch origin main
  git worktree add -b <branch> ../homelab-<task> origin/main
  ```

- Re-prompt a task that is already in progress instead of opening a second
  worktree for the same issue. Never work inside another task's checkout.

## Never discard uncommitted work

Never remove a worktree that has uncommitted changes. Commit them to the
worktree's own branch first so they cannot be lost — a throwaway local
`wip(<scope>): …` commit is acceptable. It stays local; squash it or amend it
into the real commit before the PR (it is never pushed as the final message).

## Prove a branch landed before deleting it

Homelab squash-merges every PR, so the merge commit's SHA differs from the
branch's. `git branch --merged main` is **not** evidence, and a branch can read
`ahead N` and still be fully merged — that is squash, not unmerged work.

Prove it landed by checking that the files the branch touched carry no remaining
diff against `origin/main` (empty output = landed):

```bash
git fetch origin main
git diff <branch> origin/main -- $(git diff --name-only \
  $(git merge-base origin/main <branch>) <branch>)   # empty = landed
```

## Know the worktree class before removing

Run `git worktree list` first, then match the shape:

| Shape | Example | How to remove |
|-------|---------|---------------|
| Gitignored agent worktree | `.claude/worktrees/*` | `git worktree remove <path>` |
| Sibling task worktree | `../homelab-<task>` | `git worktree remove <path>` |
| Record whose directory is gone | — | `git worktree prune` |

## Stale lock, owner process gone

Re-run the clean-tree and landed checks **first**, then unlock, then remove.
Unlocking before the checks defeats them:

```bash
# confirm clean + landed, then:
git worktree unlock <path>
git worktree remove <path>
```

## Verify the cleanup

After a cleanup pass, `git fsck` is clean and `git worktree list` shows only
real checkouts. `git worktree prune` drops records whose directories are gone.
