# 🚀 CI/CD Pipeline Documentation

This document outlines the **Trunk-Based Development** CI/CD pipeline implemented for all microservices (`auth`, `user`, `product`, `cart`, `order`, `review`, `notification`, `shipping`) in a **polyrepo** setup.

Each service repository reuses workflows from `duyhenryer/shared-workflows`:
- `pr-checks.yml` (PR validation + Slack PR events)
- `go-check.yml` (tests + optional lint + coverage artifact)
- `sonarqube.yml` (SonarCloud analysis + optional Quality Gate enforcement)
- `docker-build.yml` (wrapper: orchestrates build → sign → failure notification)
  - `docker-build-go.yml` (core build & push logic for Go services)
  - `docker-sign.yml` (Cosign keyless image signing)
- `status.yml` (final Slack status)

The pipeline follows a **"Build Once, Analyze Everywhere"** pattern: `go-check` produces a `coverage.out` artifact that `sonarqube` consumes (no need to rerun tests for analysis).

## 📊 Workflow Visualization

### 1. Orchestration Logic
This flowchart illustrates how jobs are connected and triggered based on events.

```mermaid
flowchart TD
  PullRequest[PullRequest_to_main] --> PrChecks[pr-checks]
  PullRequest --> GoCheck[go-check]
  PushMain[Push_to_main] --> GoCheck

  PrChecks --> BranchRules[Validate_branch_name]
  PrChecks --> SlackPr[Slack_PR_event_notify]

  GoCheck --> UnitTests[Run_tests_and_generate_coverage]
  UnitTests --> UploadCov[Upload_artifact_coverage-report]

  UploadCov --> Sonar[sonarqube]
  Sonar --> QualityGate[Quality_Gate_optional_enforcement]

  QualityGate --> BranchGate{Is_default_branch}
  BranchGate -->|PR| EndNode[End]
  BranchGate -->|main| DockerApp[docker-build_app_image]
  BranchGate -->|main| DockerDbInit[docker-build_db_init_image]

  DockerApp --> Notify[status]
  DockerDbInit --> Notify
  EndNode --> Notify
  SlackPr --> Notify
```

### 2. Execution Sequence
This diagram details the interaction between GitHub Actions, SonarCloud, and Slack.

```mermaid
sequenceDiagram
    autonumber
    participant Dev as Developer
    participant GA as GitHubActions
    participant PR as pr-checks
    participant Test as go-check
    participant Sonar as SonarCloud
    participant Docker as docker-build
    participant Slack as Slack

    Dev->>GA: Open_or_update_pull_request
    GA->>PR: Run_pr-checks
    PR->>PR: Validate_branch_name
    PR-->>Slack: Notify_PR_event

    GA->>Test: Run_go-check
    Test->>Test: go_test_and_generate_coverage_out
    Test->>GA: Upload_artifact_coverage-report

    GA->>Sonar: Run_sonarqube
    Sonar->>GA: Download_artifact_coverage-report
    Sonar->>Sonar: Scan_and_check_quality_gate

    alt Push_to_main
      GA->>Docker: Build_and_push_images
    end

    GA->>Slack: Final_status_notification
```

---

## 🔄 Detailed Process Flows

### 1️⃣ Flow: Pull Request (Validation)
**Trigger:** Developer opens or updates a Pull Request targeting `main`.
**Goal:** Verify code quality, security, and functionality **before** merging.

| Step | Job Name | Trigger Condition | Action & Responsibility |
|------|----------|-------------------|-------------------------|
| **1** | `pr-checks` | **PR Only** | **Gateway Check**: validates branch naming (`feat/*`, `fix/*`, etc.) and sends Slack PR-event notification. |
| **2** | `go-check` | **Always** | **Test + Coverage Artifact**: runs Go tests and uploads `coverage-report` artifact containing `coverage.out`. **Lint runs only on PR** when enabled. |
| **3** | `sonar` | **Always** | **SonarCloud Analysis**: downloads `coverage-report` and runs Sonar scan. **Quality Gate enforcement is configurable** (`fail-on-quality-gate`). |
| **4** | `notify` | **Always** | **Reporting**: posts final pipeline status to Slack (runs even if previous steps failed). |

> **Skipped on PR:** `docker` / `docker-db-init` jobs do NOT run on PRs to avoid pushing images for non-merged code.

---

### 2️⃣ Flow: Push to Main (Delivery)
**Trigger:** PR is merged into `main` (or direct push).
**Goal:** Create a release candidate and publish the artifact.

| Step | Job Name | Trigger Condition | Action & Responsibility |
|------|----------|-------------------|-------------------------|
| **1** | `go-check` | **Always** | **Regression Check**: re-runs tests and uploads fresh `coverage-report` artifact. (Lint is PR-only.) |
| **2** | `sonar` | **Always** | **Analysis Update**: updates SonarCloud main-branch analysis based on the coverage artifact. |
| **3** | `docker` | **Main Only** | **Deployment Artifact**: builds and pushes the service image to GHCR. |
| **4** | `docker-db-init` | **Main Only** | **Migration Artifact**: builds and pushes the migration image (Flyway init image) to GHCR. |
| **5** | `notify` | **Always** | **Reporting**: posts final pipeline status to Slack. |

---

## Local Verification with `act`

> **`act` is for local verification only.** It is useful for validating YAML wiring and basic job logic before pushing, but it does **not** replicate the full GitHub Actions runtime. Known limitations:
>
> - JavaScript-based actions may not work (e.g., `actions/upload-artifact`, some installer actions).
> - Secrets, OIDC tokens, and `GITHUB_TOKEN` permissions are unavailable or limited.
> - Docker-in-Docker and registry push/sign steps will be skipped or fail.
> - Artifact upload/download between jobs is not supported.
>
> **Recommendation**: Use `act` to catch YAML syntax errors, job dependency issues, and shell script bugs. Always rely on GitHub Actions (real runtime) for production correctness.

```bash
# Example: dry-run a PR workflow locally
act pull_request -W .github/workflows/ci.yml --detect-event
```

---

## Docker Image Naming Convention

GHCR auto-grants `write_package` permission to images whose name **matches the GitHub repository name**. To avoid permission errors, the `image-name` input in `docker-build.yml` must match the repo name. Migration images use the `{repo-name}-init` suffix as a separate GHCR package.

| GitHub Repo | GHCR Image (app) | GHCR Image (migration) |
|---|---|---|
| `product-service` | `ghcr.io/duynhne/product-service` | `ghcr.io/duynhne/product-service-init` |
| `auth-service` | `ghcr.io/duynhne/auth-service` | `ghcr.io/duynhne/auth-service-init` |
| `user-service` | `ghcr.io/duynhne/user-service` | `ghcr.io/duynhne/user-service-init` |

**Convention**: Always use the full GitHub repo name as `image-name` (e.g., `product-service`, not `product`). Append `-init` for migration images (e.g., `product-service-init`).

> **Note**: Helm values may reference different image names/tags (e.g., `product:v6`) that are managed separately from CI. The CI-published images and Helm-deployed images do not need to share the same GHCR repo.

---

## Shared Workflow Architecture

### Docker Build Pipeline Split

The `docker-build.yml` workflow follows a **wrapper + reusable** pattern for maintainability:

```mermaid
flowchart TD
  Caller[Service CI - ci.yml] --> Wrapper[docker-build.yml - Wrapper]
  Wrapper --> Build[docker-build-go.yml - Build and Push]
  Wrapper --> Sign[docker-sign.yml - Cosign Signing]
  Wrapper --> Fail[Failure Notification]
  Build -->|outputs: tags, digest| Sign
  Sign -.->|if push and cosign| Cosign[Keyless OIDC Sign]
  Fail -.->|if failure| Summary[GitHub Step Summary]
```

| Workflow | Responsibility |
|---|---|
| `docker-build.yml` | Thin wrapper; orchestrates build → sign → failure notification. Service repos call this. |
| `docker-build-go.yml` | Core build logic: checkout, QEMU/Buildx, GHCR login, metadata, build & push, summary. Designed for Go services; create `docker-build-node.yml` for other stacks. |
| `docker-sign.yml` | Cosign keyless (OIDC) image signing. Receives tags + digest from the build job. |

**Backward compatibility**: Service repos continue calling `docker-build.yml` with the same inputs. The split is transparent.

### Learnings from Clone-Workflow

Ideas adopted from a reference CI/CD repository:

- **Wrapper workflow pattern**: A thin top-level workflow (`docker-build.yml`) that delegates to focused reusables, rather than a single monolithic workflow. This improves readability, testing, and reuse.
- **Future extensions** (not yet implemented):
  - **PII checks**: A dedicated workflow for scanning code or config for sensitive data before build (similar to `pii-checks.yml` pattern).
  - **CI status aggregation**: A `ci-common.yml`-style wrapper that orchestrates the entire CI pipeline, reducing boilerplate in individual service repos.