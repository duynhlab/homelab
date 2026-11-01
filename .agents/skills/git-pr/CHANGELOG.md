# git-pr changelog

The skill's version is `metadata.version` in [SKILL.md](SKILL.md); the rules
for bumping it are in [AGENTS.md § Skill versioning](../../../AGENTS.md#skill-versioning).
Newest first.

## [Unreleased]

## [2.0.0] - 2026-11-01

- Renamed from `git-commits`: the skill now owns PR titles and descriptions
  as well as branch names and commits. The PR title follows the commit
  subject rules because it becomes the squash subject.
- Add § Pull requests: read the current description before updating, lead
  the Summary with why in about 100 words, list no files, report only checks
  that ran, and publish with `--body-file`.
- Add § Writing style (ASD-STE100 sentence rules, no dictionary).
- Closing keywords move to the PR description; a commit never carries one.

## [1.0.0] - 2026-10-16

- Baseline: commit and branch conventions centralised in #1281; semantic `type(scope):` subjects, the duynhne author and the duynebot co-author since #1399.
