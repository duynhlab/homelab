# ADR-074: Govern Continuous Profiling Identity, Labels and Overhead

> **Decision summary:** We will keep one shared profiler lifecycle in `pkg/obsx`
> pushing to Pyroscope, close the profile label set to four identity labels derived
> from the same resource the tracer and meter use, fix the ten profile types and
> their runtime sampling centrally, and bring `mockpay` under the contract. We
> accept that the label set narrows the deployed policy and that per-service
> disabling may not exist, in exchange for profiles that are comparable across
> services and an overhead that is budgeted rather than discovered.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-09-17 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | Application continuous profiling on every Go service and worker: lifecycle, profile types, labels, overhead and failure behaviour |
| **Affected components** | `pkg/obsx` profiling helper and tracer-provider wrapper; domain ResourceSets (`PROFILING_ENABLED`, version input); `mockpay` manifest; Pyroscope label queries and dashboards; `docs/api/profiling.md` |
| **Related RFC** | [RFC-0031](../../rfc/RFC-0031/) |
| **Related research** | [research.md](../../rfc/RFC-0031/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0031 delivery plan Tasks 1.2, 1.4, 3.3, 4.2 |
| **Adoption** | Not started |

## Context

All ten services and both worker modes already call `obsx.SetupProfiling` and push
ten profile types to Pyroscope; no service imports the Pyroscope SDK directly. That
is the cleanest instance of the shared-package rule in the fleet, and the contract
around it is the weakest. Two of the four identity labels are empty everywhere:
`service_version` because API services have no version source, and
`deployment_environment` because the profiler re-parses `OTEL_RESOURCE_ATTRIBUTES`
for a deprecated key no manifest sets, while the tracer and meter receive the
environment through a different variable under the current key. Live measurement on
Kind and local-stack showed labels the contract never named — `pyroscope_spy`,
`span_name`, and on local-stack `hostname`, `target`, `service_git_ref`,
`service_repository` — and the as-built policy's "low-cardinality deployment identity
from resource attributes" has no list, so two services can disagree and both comply.

The kill switch `PROFILING_ENABLED` is a literal per domain ResourceSet, so turning
profiling off is a GitOps commit that disables a whole domain. `mockpay` carries no
telemetry environment at all. Mutex and block profiling change process-global
runtime sampling and are configured centrally, which is right, but no overhead budget
is written down.

## Scope

### In scope

- The single profiler lifecycle, its start gate, failure behaviour and shutdown
  budget.
- The ten profile types, the exclusion of `goroutine_leak`, and central runtime
  sampling rates with an overhead budget.
- The closed four-label identity set, how it is derived, and what happens to labels
  the SDK adds.
- The scope of `PROFILING_ENABLED` and the version source for API services.
- Trace-to-profile correlation as it is actually supported.

### Out of scope

- Pyroscope deployment, retention or the profiling agent's self-observation series.
- Replacing Pyroscope.
- Grafana datasource capability for one-click trace-to-profile navigation.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Same identity as the other signals | A profile must be findable from a span's `service.name`, version and environment |
| 2 | Comparable label set | An open-ended label policy makes violations untestable |
| 3 | Budgeted overhead | Mutex and block sampling are process-global; a change is a benchmarked change |
| 4 | Non-critical to the business path | Profiling failure must never turn readiness false |
| 5 | One process outside the contract is a hole | `mockpay` is a Go process the fleet standard must cover |

## Decision

We will keep `obsx.SetupProfiling` as the only way a process profiles, and make it
derive `service_name`, `service_namespace`, `deployment_environment` and
`service_version` from the same OTel resource the tracer and meter use — not from a
second parse of the environment. Those four labels are the closed set; `span_name`
is admitted because it is what makes the CPU profile span-scoped, `pyroscope_spy` is
tolerated as a constant, and every other SDK-added label is stripped in the shared
helper. Domain services take `service_version` from the existing `image_tag` input;
`mockpay` gets an explicit version input and the full telemetry environment.

The helper owns ten profile types and excludes `goroutine_leak` by decision. Mutex
fraction and block rate are set centrally, only after a successful profiler start,
with a documented overhead budget. `PROFILING_ENABLED` is either promoted to a
per-service input or documented as domain-scoped; either way disabling it changes no
other signal and no readiness. The supported trace-to-profile workflow is manual —
`pyroscope.profile.id` on spans is evidence, not navigation — until a datasource that
can consume it is deployed and verified.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **One lifecycle** | Only `obsx.SetupProfiling` starts a profiler; no service imports `pyroscope-go` or sets `runtime.SetMutexProfileFraction` / `SetBlockProfileRate` |
| **Start gate** | The profiler starts only after endpoint and identity validation; runtime sampling rates are applied only after a successful start |
| **Failure** | Startup or upload failure emits a sanitised warning without credentials or the full endpoint and never affects readiness |
| **Identity** | Labels come from the shared OTel resource; `deployment_environment` maps from `deployment.environment.name`, `service_version` from `service.version` |
| **Closed set** | Exactly `service_name`, `service_namespace`, `deployment_environment`, `service_version`, plus `span_name` on span-scoped CPU profiles and the constant `pyroscope_spy`; anything else is stripped |
| **Forbidden** | No user, workflow, run, request, trace, order, session, payment, SKU or pod identifier, raw path, address, secret or arbitrary input as a label |
| **Types** | CPU, alloc objects/bytes, inuse objects/bytes, goroutine, mutex count/duration, block count/duration; `goroutine_leak` excluded until an overhead measurement and a consumer exist |
| **Overhead** | Mutex fraction and block rate are central constants with a written budget; a change requires a workload benchmark |
| **Shutdown** | Stop is attempted within the process shutdown budget after work drains; tests bound it because the SDK's stop ignores its context |
| **Correlation** | `pyroscope.profile.id` is added to spans when both signals are on; documentation claims no one-click link the deployed datasource cannot perform |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — One shared lifecycle, resource-derived closed label set, central types and rates, `mockpay` included** | Comparable identity; testable violations; overhead budgeted | Narrows the deployed policy; label stripping is shared-helper work | Selected |
| **B — Preserve Pyroscope with stricter shared contracts** | No backend change | None beyond A; stated for scope | Selected with A |
| **C — Keep the open-ended "low-cardinality identity" policy** | No change | Untestable; two compliant services can disagree | Rejected |
| **D — Let services add labels by configuration** | Flexibility | Cardinality and privacy risk moves to each team; contradicts the shared-package rule | Rejected |
| **E — Include `goroutine_leak` now** | Complete type set | No consumer, no alert, no overhead measurement | Rejected until measured |

### Why the selected option won

It fixes two live defects — empty labels caused by a second environment parse and an
unversioned fleet — by making the profiler read the resource every other signal
already uses, and it turns the label policy into a set a test can count.

### Why the closest alternative lost

The open-ended policy is the as-built state, and live measurement showed it produces
six undeclared labels across two environments with no way to call any of them a
violation.

## Consequences

### Positive consequences

- Every profile is findable from a span by identical identity attributes.
- `service_version` and `deployment_environment` are populated on every process, so
  version annotations on cluster dashboards stop being blank for API services.
- Overhead is a written budget with a benchmark behind changes.

### Negative consequences and accepted trade-offs

- Labels the SDK adds by default are stripped in the shared helper, which is code the
  platform must maintain across SDK upgrades.
- Domain-scoped `PROFILING_ENABLED` may remain; the operational doc then says so
  plainly rather than implying a per-service switch.
- Trace-to-profile navigation remains a manual query.

### Neutral consequences

- The profiling agent's self-observation series keep their Kubernetes discovery
  labels; they are platform self-observation and never appear on application profiles.
- Profile types and Pyroscope deployment are unchanged.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Derive profiler labels from the shared OTel resource; strip undeclared labels | `duynhlab/pkg` | RFC-0031 Task 1.4 | Pyroscope label-names query returns exactly the closed set per service |
| Wire `service.version` from `image_tag` in domain ResourceSets; add `mockpay` telemetry and version inputs | Platform GitOps | RFC-0031 Tasks 1.2, 3.3 | `service_version` non-empty on every process |
| Decide and document the scope of `PROFILING_ENABLED` | Platform GitOps, docs | RFC-0031 Task 1.4 | Manifest and `docs/api/profiling.md` agree |
| Write the overhead budget and the mutex/block benchmark procedure | `duynhlab/pkg` | RFC-0031 Task 1.4 | Budget stated in the shared-package contract |
| Publish the as-built profiling contract | Platform docs | RFC-0031 Task 4.3 | `docs/api/profiling.md` matches deployment |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Closed label set | Pyroscope querier label-names call per service returns exactly the declared set; label-values for `deployment_environment` and `service_version` are non-empty |
| Failure isolation | Profiler pointed at an unreachable endpoint: readiness stays true, one sanitised warning, no other signal changes |
| Runtime rates | Test asserts mutex fraction and block rate are unchanged when the profiler fails to start |
| Types | Profile-types query returns the ten declared types and not `goroutine_leak` |
| Shutdown | Test bounds stop within the process budget with an unreachable server |
| Correlation | Spans carry `pyroscope.profile.id` when both signals are on; docs describe the manual workflow only |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- A datasource that consumes `pyroscope.profile.id` for navigation is deployed and
  verified.
- An alert or runbook needs `goroutine_leak`, with an overhead measurement attached.
- A workload benchmark shows the central mutex or block rate breaching the budget.
- The Pyroscope SDK changes its default label set in a way the stripping cannot follow.

A changed decision requires a new ADR that supersedes this one.

## References

- [RFC-0031](../../rfc/RFC-0031/) — § Continuous profiling contract, § Resource and propagation contract
- [RFC-0031 research](../../rfc/RFC-0031/research.md) — § Live verification
- [Profiling contract (as-built)](../../../api/profiling.md)
- [Profiling platform guide](../../../observability/profiling/README.md)
- [Shared package contract (as-built)](../../../api/pkg.md)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-09-17 | Proposed / Not started | Drafted during RFC-0031 architecture review from § Continuous profiling contract and the live label measurements |
| 2026-09-17 | Accepted / Not started | Owner accepted with the RFC; created at `Accepted` per the RFC-0028/RFC-0030 precedent |

---
_Last updated: 2026-09-17._
