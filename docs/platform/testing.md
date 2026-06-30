# Testing & Coverage Standard

How the Go microservices are tested, how coverage is measured, and how the CI
enforces it. Pairs with [`sonarcloud.md`](sonarcloud.md) (quality gate) and
[`cicd.md`](cicd.md) (pipeline).

## Layered testing (Web / Logic / Core)

Tests follow the 3-layer architecture (see [`../api/api.md`](../api/api.md)). The
layer boundaries are the natural test seams:

| Layer | Package | Tested as | What it mocks |
|-------|---------|-----------|---------------|
| Web | `internal/web/v1` | unit — `httptest` + gin test mode | the Logic service interface |
| Logic | `internal/logic/v1` | unit — pure | the repository interface (ports) |
| gRPC | `internal/grpc/v1` | unit — call handlers directly | the Logic service interface |
| Cross-cutting | `middleware` | unit — `httptest` + table-driven | — |
| Config | `config` | unit — env-driven | — |
| Core / repository | `internal/core/repository` | **integration** — real Postgres | nothing (real DB) |

## Conventions (match the existing repos)

- **Stdlib `testing` only** — no testify, no gomock for unit tests.
- **Hand-written mocks**: a struct implementing the interface with configurable
  result/err fields.
- **Table-driven** subtests.
- The only test-only dependency allowed is **testcontainers** (integration only).
- Prefer the `golang-pro` workflow: `golangci-lint` + table-driven + `-race`.

## Integration tests (testcontainers)

The repository/data layer is tested against a **real PostgreSQL** — not mocked,
not excluded.

- File lives next to the impl, build-tagged so the default unit run skips it:
  ```go
  //go:build integration
  ```
- Uses `github.com/testcontainers/testcontainers-go` + `.../modules/postgres`:
  start Postgres, apply `db/migrations/sql/*.up.sql`, exercise each repository
  method (incl. not-found / idempotent paths).
- **Wait strategy — important.** Use the log-based wait, NOT `ForListeningPort`
  (the port opens during initdb's transient first start, then the server
  restarts → connection reset → flaky/hung tests):
  ```go
  testcontainers.WithWaitStrategy(
      wait.ForLog("database system is ready to accept connections").
          WithOccurrence(2).
          WithStartupTimeout(90 * time.Second),
  )
  ```
- **Test-only footprint.** testcontainers pulls the Docker SDK into `go.mod` as
  indirect deps, but behind the `integration` tag — `go build ./...` does **not**
  link it into the service binary (verify: the binary build stays clean).
- Run locally (needs a Docker daemon):
  ```bash
  go test -tags=integration ./internal/core/repository/...
  ```

## CI wiring (shared workflows in `gha-workflows`)

`go-check.yml` and `sonarqube.yml` support the integration + merged-coverage flow.
Each service wires it in **both** `build.yml` (push) and `check.yml` (PR):

```yaml
go-check:
  uses: duynhlab/gha-workflows/.github/workflows/go-check.yml@main
  with:
    command-test: 'go test -race -coverprofile=coverage.out ./...'
    lint: true
    integration: true
    integration-command: 'go test -tags=integration -covermode=atomic -coverprofile=coverage-integration.out ./internal/core/repository/...'
  secrets: inherit

sonar:
  needs: [go-check, gitleaks]
  uses: duynhlab/gha-workflows/.github/workflows/sonarqube.yml@main
  with:
    project-key: 'duynhlab_${{ github.event.repository.name }}'
    organization: 'duynhlab'
    integration-coverage: true   # merge coverage-integration.out into the report
  secrets:
    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

- The `integration` job runs on `ubuntu-latest`, which ships a **running Docker
  daemon** — testcontainers spawns sibling Postgres containers on the runner host.
  We do **not** use docker-in-docker or socket-mounting into a job container.
- The job uploads `coverage-integration.out`; the Sonar job downloads it and
  passes `sonar.go.coverage.reportPaths=coverage.out,coverage-integration.out`,
  so the **repository layer's integration coverage counts** toward the gate.

### Execution model & image-pull cost

- **Runs on the runner host, not inside a job container.** testcontainers talks
  to the runner's own Docker daemon and starts Postgres as a **sibling** container.
  We deliberately do **not** run `go test` inside a container with the Docker
  socket mounted, nor docker-in-docker — that adds networking complexity (the
  test process can't reach the mapped port by `localhost`) for no benefit here.
- **Each run pulls `postgres:16-alpine`** (~tens of seconds) — a clean runner has
  no image cache. This is the main cost of the integration job; budget for it
  (the unit job stays fast and independent).
- **Alternatives considered (and why not):**
  - A GitHub Actions `services:` Postgres is faster but loses testcontainers'
    ergonomics — programmatic lifecycle, applying the repo's real migrations, and
    per-test isolation. We chose fidelity (real schema, real driver) over a few
    seconds. Revisit with image caching / a pinned digest if pull time bites.
  - docker-in-docker / socket-mount-into-container: rejected (complexity above).
- **Local gotcha:** running the integration suite many times can saturate the
  local Docker daemon (leftover containers → `pgxpool.Pool.Close` / ryuk hangs).
  Clean up with `docker rm -f $(docker ps -aq --filter label=org.testcontainers=true)`.
  CI runners are fresh each run, so this only affects local loops.

## Linting (`golangci-lint`)

CI's lint job runs **`golangci-lint` v2.6.0** with the repo's `.golangci.yml` —
much stricter than `go vet`. It MUST pass. Verify locally before pushing:

```bash
golangci-lint run --timeout=5m --config=.golangci.yml ./...
```

- **`unparam` gotcha.** Do not call an unexported helper from tests with the
  **same constant arguments** it receives in production — `unparam` then reports
  the parameter as "always receives X". Test generic helpers (e.g.
  `getEnvDurationSeconds(key, default)`) with **varied** keys/defaults; that is
  real coverage, not linter-gaming.

## Coverage policy

- **Quality gate: ≥ 80% coverage on new code** (configured in SonarCloud — see
  [`sonarcloud.md`](sonarcloud.md)).
- **Coverage exclusions** (counted-against-% only; still analyzed for issues),
  via the `coverage-exclusions` input of `sonarqube.yml`:
  `**/cmd/**`, `**/internal/core/database.go`, `**/db/migrations/**`,
  `**/mocks/**`, `**/*_mock.go` — bootstrap/wiring/migrations/generated code.
- The repository layer is **NOT excluded** — it is integration-tested and merged
  into the report (above).

## Pre-push checklist (per service)

```bash
go build ./...                                              # binary builds (no testcontainers linked)
golangci-lint run --config=.golangci.yml ./...             # 0 issues
go test -race ./...                                         # unit, green
go test -tags=integration ./internal/core/repository/...   # integration, green (needs Docker)
```
