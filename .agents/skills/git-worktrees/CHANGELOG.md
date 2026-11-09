# git-worktrees changelog

The skill's version is `metadata.version` in [SKILL.md](SKILL.md); the rules
for bumping it are in [AGENTS.md § Skill versioning](../../../AGENTS.md#skill-versioning).
Newest first.

## [Unreleased]

## [1.1.0] - 2026-11-09

- Worktrunk (`wt` 0.81) is the preferred interface; every rule keeps a
  plain-Git fallback and a tool-detection step.
- New worktrees live at `../homelab.<branch>` (Worktrunk's default path
  template); `../homelab-<task>` and `.claude/worktrees/*` become legacy rows
  in the removal table.
- The landed check changes: the per-file diff against `origin/main` reported
  three merged branches (#1515, #1516, #1518) as unmerged once `main` had
  moved on the same files. Evidence is now `wt list` `_`/`⊂`, `wt remove`'s
  refusal, or a patch-id match with the `(#N)` squash commit.
- New sections: commands this repo never runs (`wt merge`, `wt step push`,
  `wt step promote`, `wt remove -f`/`-D`, `wt step commit`, bare
  `wt step prune`), shared-environment limits, and the no-project-config
  decision.

## [1.0.1] - 2026-11-01

- Link to git-pr after the git-commits rename (#1473).

## [1.0.0] - 2026-10-28

- Baseline: worktree lifecycle and squash-merge-aware cleanup, added in #1401.
