# Ruleset Automation with gh-patcher

## What is gh-patcher?

[gh-patcher](https://github.com/duynhlab/gh-patcher) is a CLI tool that batch-applies GitHub branch rulesets across an entire organization via the GitHub REST API. It replaces the need to manually configure branch protection rules on every repository.

## Why is it needed?

GitHub **Free** and **Team** plans do not support **organization-level rulesets** (that feature requires Enterprise). Without org-level rulesets, every repository needs its own branch protection configuration — tedious to set up manually and easy to forget for new repos.

`gh-patcher` solves this by:

- Listing all repos in the org
- Filtering by regex (`REPO_PATTERN`)
- Applying a standard branch ruleset to each matching repo
- Running idempotently — safe to re-run daily

## Daily automation

A GitHub Actions workflow runs `gh-patcher` every day at 2:00 AM UTC:

```yaml
# .github/workflows/apply-rulesets.yml (in the gh-patcher repo)
on:
  schedule:
    - cron: '0 2 * * *'
  workflow_dispatch:
    inputs:
      dry_run:
        description: 'Dry run (true = preview only)'
        default: 'false'
```

This ensures new repositories automatically get the standard ruleset within 24 hours of creation.

## How GitHub builds status check names

When a caller workflow invokes a reusable workflow, GitHub constructs the status check name as:

```
{caller job ID} / {reusable job name}
```

For example, with this caller:

```yaml
name: Check               # ← workflow name (display only)

jobs:
  go-check:                # ← caller job ID (used in check name)
    uses: org/shared/.github/workflows/go-check.yml@main
```

And this reusable workflow containing a job named `Test`, the actual check run name for ruleset matching is:

```
go-check / Test
```

The GitHub UI displays it with additional context: `Check / go-check / Test (pull_request)`, but the shorter form is what rulesets match against. Use `gh pr checks` or the Check Runs API to find the exact name.

### Why split into check.yml + build.yml

Splitting into two files keeps concerns separated:

| File | Trigger | Purpose |
|------|---------|---------|
| `check.yml` | `pull_request` only | Tests, lint, SonarCloud |
| `build.yml` | `push` only | Docker build, scan, sign |

The ruleset-required check is: **`go-check / Test`**

## Configuration

### Key environment variables

| Variable | Description | Example |
|----------|-------------|---------|
| `GITHUB_TOKEN` | Fine-grained PAT with org admin + repo access | (stored as `GH_PATCHER_TOKEN` secret) |
| `GITHUB_ORG` | Target GitHub organization | `duynhlab` |
| `REPO_PATTERN` | Regex to match repos (space-separated alternatives = OR) | `.*-service frontend pkg` |
| `REPO_EXCLUDE_PATTERN` | Regex to exclude repos | `^$` |
| `STATUS_CHECK_CONTEXTS` | Comma-separated required check names | `go-check / Test` |
| `DRY_RUN` | Preview mode (no writes) — defaults to `true` | `false` |

### Setting up `GH_PATCHER_TOKEN`

1. Go to **GitHub Settings > Developer settings > Personal access tokens > Fine-grained tokens**
2. Create a token scoped to the `duynhlab` organization with:
   - **Repository access**: All repositories
   - **Permissions**: Administration (Read and Write), Contents (Read and Write), Metadata (Read)
3. Store the token as `GH_PATCHER_TOKEN` in the `gh-patcher` repository secrets

### Adjusting STATUS_CHECK_CONTEXTS

When your CI workflow structure changes (e.g., renaming the caller job ID), update `STATUS_CHECK_CONTEXTS` in `apply-rulesets.yml` to match the new check name.

To find the exact check name:
1. Open any PR in one of the target repos
2. Look at the **Checks** tab — the name shown there is the exact context string
3. Set `STATUS_CHECK_CONTEXTS` to that value

## Ruleset definition

The standard branch ruleset (`gh-standard-branch-ruleset`) enforces:

- **No force push** (non_fast_forward)
- **No branch deletion** (deletion)
- **Required status checks** — configurable via `STATUS_CHECK_CONTEXTS`
- **Required pull request reviews** — at least 1 approval, dismiss stale reviews

See [gitflow.md](gitflow.md) section 7 for the full ruleset specification.

## Links

- [gh-patcher repository](https://github.com/duynhlab/gh-patcher)
- [Gitflow standard](gitflow.md)
- [CI/CD documentation](cicd.md)
- [Check template](check_template.yml) / [Build template](build_template.yml)
