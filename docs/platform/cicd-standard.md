# CI/CD Standard

> **Audience:** every repo owner in the `duynhlab` org.
> **Status:** the baseline a repository must meet to be considered production-grade.
> **Scope:** GitHub Actions CI/CD built on the shared reusable-workflow library
> [`duynhlab/gha-workflows`](https://github.com/duynhlab/gha-workflows). This doc is the
> *policy*; the *how-to* lives in [`cicd.md`](cicd.md) (pipeline), [`gitflow.md`](gitflow.md)
> (branching/releases), [`ruleset-automation.md`](ruleset-automation.md) (branch protection),
> and [`sonarcloud.md`](sonarcloud.md) (quality gate).
>
> This standard assumes **GitHub-hosted runners** and was adversarially reviewed against
> GitHub's security-hardening guidance.

## 1. Principles

1. **Shift left** — lint/secret-scan/test/scan run on the PR, before merge.
2. **Faster is safer** — small PRs, squash-merge, frequent releases.
3. **Least privilege** — every workflow declares the minimum `permissions:` it needs.
4. **Supply-chain integrity** — third-party actions pinned to immutable SHAs; images scanned
   before push, signed (keyless/OIDC), and **verified at admission**.
5. **Immutability** — production runs an image **digest** (`sha256:…`); tags are mutable.
6. **One way to do it** — repos consume the shared workflows; they do not fork CI logic.

## 2. Reusable-workflow catalog (`duynhlab/gha-workflows`)

| Workflow | Purpose | Used on |
|----------|---------|---------|
| `pr-checks.yml` | branch-name policy + Slack PR thread | PR |
| `go-check.yml` | `go test -race` + coverage + golangci-lint | PR, push |
| `gitleaks.yml` | secret scan (SARIF) | PR, push |
| `sonarqube.yml` | SonarCloud quality gate | PR, push |
| `docker-build-go.yml` / `-node.yml` | build, **scan-before-push** (Trivy), SBOM, push | push |
| `trivy-scan.yml` | post-push CVE report (SARIF) | push |
| `docker-sign.yml` | Cosign keyless signing (OIDC) | push |
| `tf-lint.yml` | `terraform fmt` + TFLint | PR (IaC repos) |
| `status.yml` | Slack/Sheets run status | PR, push |

Composite actions: `.github/actions/{gitleaks,slack-notification}`.

## 3. Action pinning & reusable-workflow refs

- **Third-party actions → full 40-char commit SHA**, with a trailing `# vX.Y.Z` comment:
  `uses: docker/build-push-action@<sha> # v7`. A mutable tag (`@v4`) is a remote-code-execution
  vector if the action is compromised. Renovate keeps SHAs current (§9), so pinning ≠ staleness.
- **First-party reusable workflows → `@main` today.** Be honest about the tradeoff: `@main` is
  **mutable** — a careless/compromised merge to `gha-workflows` changes CI/CD for *all*
  consumers with no consumer PR. The **only immutable** ref is a SHA; a future `@v1` major tag
  (§10) improves compatibility management but is **still mutable** (a major tag can be moved) —
  do not call `@v1` "pinning." `@main` is the current accepted tradeoff for an internal,
  CODEOWNER-gated library; high-blast-radius consumers may pin a SHA.

## 4. Least-privilege permissions

Set `permissions:` at the **caller** (top level = deny-all baseline, widen per job). Reusable
workflows declare the scope their job needs.

| Job / workflow | Required permissions |
|----------------|----------------------|
| go-check, tf-lint, pr-checks (validate) | `contents: read` |
| gitleaks, trivy-scan | `contents: read`, `security-events: write`, **`actions: read`** (SARIF upload in private repos) |
| sonarqube | `contents: read`, `pull-requests: read` |
| docker-build-* | `contents: read`, `packages: write` |
| docker-sign | `contents: read`, `packages: write`, `id-token: write` (OIDC) |
| status / Slack | `actions: read` (list jobs); add `statuses: write` only if it posts commit status |

- **Never `secrets: inherit`** — pass only named secrets. (Note: `workflow_call` cannot pass
  *environment* secrets; a called job that sets `environment:` reads that environment's secrets.)
- **Gate privileged jobs to trusted refs/events.** Any job with `packages: write` or
  `id-token: write` MUST run only on push to `main`/release tags (or a declared environment) —
  `if: github.event_name == 'push' && github.ref == 'refs/heads/main'` or tag — **never on
  fork PRs or arbitrary `workflow_dispatch`**. `id-token: write` is job-wide: keep the signing
  job isolated from build/test/untrusted third-party actions.

## 5. Untrusted input & injection

Attacker-controllable context includes `github.head_ref`, **branch/tag names, commit messages,
PR title/body, issue comments, labels, author fields, changed file paths, and
`workflow_dispatch` inputs**. Do **not** interpolate them into `run:`/`script:`. Pass via `env:`
and reference the shell variable.

> `env:` only prevents *template-time* injection — it is still unsafe under unquoted expansion,
> `eval`, `bash -c`, heredocs, JSON construction, `github-script`, or Docker build-args. Quote
> and treat as data everywhere.

`pull_request_target` is **forbidden** to check out or execute PR-head code while secrets / a
write token are in scope.

## 6. Concurrency

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true     # PR/CI only
```

- **Deploy/release: `cancel-in-progress: false`**, and be aware GitHub keeps only **one** queued
  run — design releases so a dropped intermediate run is safe (or serialize deliberately).
- **Build → push → sign must not be cancellable mid-chain.** A cancel after `push` but before
  `docker-sign` leaves an **unsigned** image in GHCR. Keep push+sign in one `needs` chain guarded
  so signing always runs for a pushed digest (or sign in the same job).

## 7. Image security

- **Scan before push — calibrated gate** (Trivy): **block the push only on `CRITICAL`** (fixable);
  **report `HIGH`/`MEDIUM`** in the job summary + Security tab **without blocking**. Driven by
  `scan-block-severity` (default `CRITICAL`) vs `scan-severity` (report set, default
  `CRITICAL,HIGH`), with `--ignore-unfixed`. Rationale: a freshly-disclosed `HIGH` in a base image
  that has **no upstream fix yet** must not block every service from shipping — that's how you end
  up unable to deploy through no fault of your own. Accept a *specific* CVE only via a **time-boxed
  `.trivyignore.yaml`** (`expired_at:` + a statement), never by loosening the gate globally. The
  pre-push scan writes a **severity table + CVE list to the job summary** so failures are visible.
- **Base images:** `:latest` is mutable and makes scans non-deterministic (same Dockerfile passes
  or fails depending on what the registry served). **Pin a digest** (Renovate-managed) and
  **rebuild on a schedule** so base fixes land automatically — or use **Copacetic** to patch OS
  CVEs in-image. Keep a best-effort `apk --no-cache upgrade` in the runtime stage.
- **Sign** every pushed image with Cosign keyless OIDC — including the **`-init`** image.
- **Naming is multi-level** (platform convention): `ghcr.io/duynhlab/<repo>/<image>` — the `mop`
  chart renders `<name>-service/<name>` **and** `<name>-service/<name>-init`. Scan **and sign
  every** pushed image, not just the primary one.
- **TOCTOU:** bind scan result, signature, and deploy to the **same digest** — a locally-scanned
  artifact (esp. a multi-platform Buildx manifest) may differ from the pushed digest.
- **Production consumes an immutable `sha256:` digest** (GHCR tags are mutable); `vX.Y.Z`/
  `:latest` are human conveniences only.
- **Verification, not just signing:** an unverified signature is metadata. Admission
  (Kyverno — see [`kyverno.md`](kyverno.md)) MUST verify the Cosign signature with **strict
  certificate identity** (OIDC issuer = GitHub, expected repo + ref/workflow) and reject
  unsigned/wrongly-signed images.

## 8. Required checks / branch protection

Enforced via Rulesets (see [`ruleset-automation.md`](ruleset-automation.md)). Required checks
are **per repo type** — `go-check / Test` is meaningless on the Node frontend or the IaC repo:

| Repo type | Required checks on `main` (block merge) |
|-----------|------------------------------------------|
| Go service / Go library | `go-check / Test`, `gitleaks`, `sonarqube` (gate enforced) |
| Node frontend | node lint+build, `gitleaks`, `sonarqube` |
| Kubernetes / IaC (`homelab`) | manifest `validate`, `tf-lint`, `gitleaks` |

All `main`: 1 approval + CODEOWNERS, linear history, signed commits, no force-push. `v*` tags:
restrict create/delete/**update** (prevents tag retargeting → immutable releases).

Caveats:
- **SonarCloud:** a required *job* ≠ gate enforced. The workflow must wait for and **fail on**
  the quality-gate result (`fail-on-quality-gate: true`), else "passing" is hollow.
- **Skipped ≠ passed:** with path filters / skip logic, a required check that never runs leaves
  the PR **pending forever**. Use an always-running **aggregator** job as the required check.
- **Fork / Dependabot PRs** lack write perms + secrets, so SARIF-upload / Slack steps degrade —
  don't hard-require a job that can't run on a fork; split scan (always) from upload (gated).

## 9. Supply-chain automation

- **Renovate/Dependabot** on every repo: Go modules, Dockerfiles, **and `github-actions`** (so
  SHA pins auto-bump). `homelab` already runs Renovate; extend the same config to all repos.
- Base images updated on a schedule; Trivy gates regressions on the next build.

## 10. Reusable-workflow versioning (target)

Consumers pin `@main` today (§3). **Target:** release `gha-workflows` with semver — `vX.Y.Z` +
a moving `v1` major tag — so consumers pin `@v1` (auto-patches, fewer surprise breaks).
Migration is a separate tracked effort; this documents the goal.

## 11. Environments, secrets, retention

- **Secrets** in GitHub Secrets / OpenBAO — never in YAML. CI holds no prod secrets; signing
  uses OIDC. Note: GitHub log redaction is best-effort — mask transformed/derived secrets
  explicitly and audit logs.
- **GitHub Environments** (`dev`/`staging`/`prod`) only gate anything if the deploy/sign/promote
  job **declares `environment: prod`** — add it, with required reviewers on prod.
- **Artifact retention:** coverage `retention-days: 1`; prune old GHCR tags on a schedule; keep
  SBOM/signature attestations with the digest.

## 12. Observability (DORA)

Emit the four DORA signals from `status.yml` run data (already shipped to Google Sheets):
deployment frequency, lead time, change-failure rate, MTTR — on a Grafana dashboard against
VictoriaMetrics (see [observability](../observability/README.md)).

## 13. Additional hardening

- **Checkout in privileged jobs:** `persist-credentials: false` so the job token isn't left in
  local git config for build scripts / compromised tools.
- **Runners:** GitHub-hosted only. If self-hosted is ever introduced, untrusted PR code must
  never run on it (persistent-compromise / cross-job risk).
- **Cache/artifact trust boundary:** a PR-controlled cache or artifact must not be consumed by a
  privileged push/sign/deploy job without integrity checks.
- **Org-level enforcement:** several "MUST"s here are advisory without org rules — set an org
  ruleset / required-workflow, an action allowlist (or SHA-pin policy), disable
  Actions-created-PR approvals, and restrict the fork-PR `GITHUB_TOKEN` to read.

## 14. New-repo adoption checklist

- [ ] `check.yml` (PR) + `build.yml` (push) call the shared workflows (see
      [`build_template.yml`](build_template.yml) / [`check_template.yml`](check_template.yml)).
- [ ] `permissions:` per §4; privileged jobs gated to trusted refs; concurrency per §6.
- [ ] `.github/CODEOWNERS` present; Rulesets applied per §8 (per repo type).
- [ ] Renovate enabled (Go + Docker + github-actions).
- [ ] Images multi-level named, scanned + signed (incl. `-init`); prod pins **digest**;
      admission verifies signatures.
- [ ] Secrets via Secrets/OpenBAO; signing via OIDC; prod jobs declare `environment:`.

## 15. Known follow-ups (post-transfer review)

- **Base-image determinism:** pin runtime base digests (Renovate) + a scheduled nightly rebuild
  (or Copacetic) so base-image CVE fixes land automatically — instead of `alpine:latest` (§7).
- Cut `@v1` tags on `gha-workflows` and migrate consumers off `@main` (§3/§10).
- Add Kyverno Cosign **signature-verification** policy with strict cert-identity (§7) — today
  signing is unverified.
- Add `actions: read` to the gitleaks/trivy reusable-workflow jobs (private-repo SARIF).
- Gate `packages:`/`id-token: write` jobs on trusted refs in the shared workflows (§4).
- Normalize consumer drift: SonarCloud `project-key` (dynamic vs hardcoded) and Trivy severity
  thresholds (build vs check).
- Remove the dead `go-version` input from `sonarqube.yml` (unused; next interface bump).
