# Application Profiling

Continuous profiling contract for every Go service and worker in the platform service catalog — `obsx.SetupProfiling`, profile types, environment variables, and trace correlation.

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **Client** | `obsx.SetupProfiling()` (`duynhlab/pkg`), `pyroscope-go` SDK — push every 15s | — |
| **Default** | On in cluster and local-stack (`PROFILING_ENABLED=true`) | — |
| **Correlation** | `pyroscope.profile.id` on spans via `otel-profiling-go` | — |
| **Platform backend** | [Profiling (platform)](../observability/profiling/README.md) — Pyroscope Helm, RustFS, Grafana | — |
| **Cross-cutting** | [Application observability](./observability.md) | — |
| **Design record** | — | **[RFC-0031](../proposals/rfc/RFC-0031/) (Accepted 2026-09-17, not yet as-built)** → [ADR-074](../proposals/adr/ADR-074-continuous-profiling-contract/) (profile identity, labels) |

---

## Overview

Every Go service pushes pprof data to Pyroscope via the shared **`obsx.SetupProfiling()`** helper — not bespoke profiler code per service. Profiles answer *which line of code* burned CPU or allocated memory during live traffic.

Shared bootstrap and cross-signal label rules: [Application observability](./observability.md).

> **Target contract — RFC-0031, `Accepted` 2026-09-17, not yet as-built** ([ADR-074](../proposals/adr/ADR-074-continuous-profiling-contract/) (profile identity, labels)).
> The profile label set closes to exactly **`service_name`, `service_namespace`,
> `deployment_environment`, `service_version`** (plus `span_name` on span-scoped CPU
> profiles and the SDK constant `pyroscope_spy`), derived from the **same OTel
> resource** the tracer and meter use — today the helper re-parses
> `OTEL_RESOURCE_ATTRIBUTES` for the deprecated key `deployment.environment`, which no
> manifest sets, so `deployment_environment` is empty fleet-wide; `service_version`
> was empty on every API service until 2026-09-18, when the domain ResourceSets put
> `service.version=<image_tag>` into `OTEL_RESOURCE_ATTRIBUTES` (RFC-0031 Task 1.2) —
> the helper already reads that key, so the label populates on the next rollout. The
> SDK's eleventh type `goroutine_leak` is excluded
> by decision; mutex and block sampling rates stay central with a written overhead
> budget; `mockpay` is brought under the contract; `PROFILING_ENABLED` became a
> per-service input on 2026-09-18 (the one part of this contract already as-built). The
> [§ Profile label policy](#profile-label-policy) below is the **as-built** policy and
> is deliberately wider than the target; it is rewritten at Task 1.4.

---

## Profile types

`obsx.SetupProfiling()` registers **10 Go profile types**:

| Profile type | pprof source | Answers |
|---|---|---|
| `ProfileCPU` | CPU | Which functions burn CPU time? |
| `ProfileAllocObjects` | alloc | What allocates the most *objects* (GC pressure)? |
| `ProfileAllocSpace` | alloc | What allocates the most *bytes*? |
| `ProfileInuseObjects` | heap | What is holding live objects (leaks)? |
| `ProfileInuseSpace` | heap | What is holding live bytes (resident heap)? |
| `ProfileGoroutines` | goroutine | Where are goroutines piling up (leaks/stalls)? |
| `ProfileMutexCount` / `ProfileMutexDuration` | mutex | Lock contention (count + wait time) |
| `ProfileBlockCount` / `ProfileBlockDuration` | block | Where goroutines block (chan/IO/sync) |

CPU, alloc, and inuse are on by default in the SDK; goroutine, mutex, and block are explicitly enabled. **Mutex/block** require Go runtime sampling (below) — without it, those four ship empty.

---

## Setup (`pkg/obsx/profiling.go`)

- **Identity** = `OTEL_SERVICE_NAME` → Pyroscope `service_name` (same as traces and metrics).
- **Labels** from `OTEL_RESOURCE_ATTRIBUTES`, dotted keys underscored: `service.namespace` → `service_namespace`, etc.
- **Runtime sampling** after successful start — `runtime.SetMutexProfileFraction(100)` and `runtime.SetBlockProfileRate(100_000_000)` (blocking events ≥ 100 ms). Only on success avoids overhead when misconfigured.
- **Strict helper validation** — empty `PYROSCOPE_ENDPOINT` returns an error; `sync.Once` guards startup and **caches the error permanently** (a second call after a failed first call returns the same error without retrying).
- Verified signature (`duynhlab/pkg`, 2026-07-29): `obsx.SetupProfiling() (func(context.Context) error, error)` — no arguments; the returned stop function flushes and stops the profiler (its context is currently ignored).

## Failure, readiness, and shutdown policy

`obsx.SetupProfiling` performs strict configuration validation and returns an
error when profiling cannot be initialized.

Profiling is non-critical to the application data path. Unless a service
contract explicitly records a stricter requirement, the process logs a
sanitized warning and continues without profiling. A profiling failure does
not make application readiness false — core app dependencies still determine
readiness.

Canonical wiring (the contract shape every service and worker converges on —
gated on `cfg.Profiling.Enabled` from `PROFILING_ENABLED`, bounded stop, stop
error always logged):

```go
func initProfiling(cfg *config.Config, logger *zap.Logger) func() {
    if !cfg.Profiling.Enabled {
        logger.Info("Profiling disabled (PROFILING_ENABLED=false)")
        return func() {}
    }

    stop, err := obsx.SetupProfiling()
    if err != nil {
        logger.Warn("Failed to initialize profiling", zap.Error(err))
        return func() {}
    }

    logger.Info("Profiling initialized", zap.String("endpoint", cfg.Profiling.Endpoint))

    return func() {
        shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.GetShutdownTimeoutDuration())
        defer cancel()
        if err := stop(shutdownCtx); err != nil {
            logger.Error("Profiling shutdown error", zap.Error(err))
        }
    }
}
```

Do not log a profiler URL containing credentials or query secrets at startup
(the `endpoint` field is the credential-free cluster DNS address).

---

## Profile label policy

Allowed profile labels:

- `service_name`, service namespace, environment, service version;
- low-cardinality deployment identity from resource attributes.

Forbidden profile labels:

- user, order, payment, session, or workflow IDs;
- email, phone, or address;
- tokens or secrets;
- request paths with embedded IDs;
- arbitrary user input.

Full classification: [cross-signal data policy](./observability.md#cross-signal-data-and-privacy-policy).

---

## Runtime overhead

The shared helper enables CPU, allocation, in-use, goroutine, mutex, and block
profiles. Mutex and block profiles add runtime sampling overhead — treat them
as higher-cost signals than CPU-only profiling.

- Disable profiling with `PROFILING_ENABLED=false` when investigating overhead.
- Revisit profile-type selection if CPU or allocation overhead exceeds the
  service's budget — do not claim a numeric overhead target unless benchmarked
  for the specific workload.
- Mutex/block sampling rates are fixed by the shared helper (verified:
  `SetMutexProfileFraction(100)`, `SetBlockProfileRate(100_000_000)` — blocking
  events ≥ 100 ms) and are applied only after a successful profiler start.

---

## Trace correlation (app side)

1. **`obsx.TracerProviderWithProfiles`** wraps the OTel `TracerProvider` with `otel-profiling-go` so spans carry **`pyroscope.profile.id`** — applied automatically inside `SetupObservability` (to the global provider) when both tracing and profiling are enabled.
2. **CPU profiles are span-scoped** — the wrapper labels CPU samples with the
   process's **root** span (`span_name`, e.g. `GET /product/v1/public/products/:id/details`);
   only that span carries `pyroscope.profile.id`, child spans do not.
3. **Heap, goroutine, mutex, and block profiles are service/time scoped** — they have no per-span correlation.
4. **Not on the four Temporal identities** (`order`, `order-worker`, `checkout`,
   `checkout-worker`). They install the replay-safe tracer provider through
   `WithTracerProviderFactory`, and obsx skips the wrapper there because it would
   change the global's concrete type that Temporal's interceptors assert on.
   Their profiles are collected normally but carry no `span_name`, and their spans
   no `pyroscope.profile.id` (measured on Kind 2026-09-24: 0 of their server spans;
   the other eight services 100%).
5. There is no one-click span→profile link — the pivot is manual:
   [Profiling (platform) § Trace correlation](../observability/profiling/README.md#trace-correlation-platform).

---

## Configuration

On by default. Injected by app ResourceSets and worker manifests:

| Env | Purpose | Default |
|-----|---------|---------|
| `PROFILING_ENABLED` | Toggle — **per-service** since 2026-09-18: the domain ResourceSets render it from the `profiling_enabled` input (default `"true"`); the two worker manifests and `mockpay` carry their own literal | `true` |
| `PYROSCOPE_ENDPOINT` | Pyroscope server | `http://pyroscope.monitoring.svc.cluster.local:4040` |
| `OTEL_SERVICE_NAME` | Identity (`service_name`) | service name |
| `OTEL_RESOURCE_ATTRIBUTES` | Labels (`service.namespace`, `deployment.environment`, `service.version`) | set by ResourceSet |

Opt one service out with `profiling_enabled: "false"` on its `ResourceSetInputProvider`
(`kubernetes/apps/services/<name>.yaml`) — a GitOps commit, per service. Before
2026-09-18 the value was a literal in the domain ResourceSet, so turning profiling off
meant every service in that domain (RFC-0031 Task 1.4). Disabling it changes no other
signal and never affects readiness.

Full env table: [Application observability § Environment variables](./observability.md#environment-variables).

### Verification (service side)

1. Check startup log: `Profiling initialized` (with the `endpoint` field), or `Failed to initialize profiling` when setup failed, or `Profiling disabled (PROFILING_ENABLED=false)`
2. Confirm env: `PROFILING_ENABLED=true`, `PYROSCOPE_ENDPOINT` reachable

Backend troubleshooting (Pyroscope pods, RustFS, Grafana datasource): [Profiling (platform) § Troubleshooting](../observability/profiling/README.md#runbook--profiles-not-appearing).

---

## References

- [Application observability](./observability.md)
- [Application tracing](./tracing.md)
- [Profiling (platform)](../observability/profiling/README.md)
- [pyroscope-go SDK](https://github.com/grafana/pyroscope-go)
- [otel-profiling-go](https://github.com/grafana/otel-profiling-go)

_Last updated: 2026-09-24 — trace correlation as measured on Kind: only the root span is labelled, the four Temporal identities carry no span labels, and the one-click link is gone (manual pivot). mockpay profiles from payment v2.4.1. Previously 2026-09-18 — `PROFILING_ENABLED` is a per-service ResourceSet input (`profiling_enabled`, default true) — RFC-0031 Task 1.4; the domain-wide literal is gone. Previously 2026-09-18 — RFC-0031 accepted: Design record moves from `None` to ADR-074 and a labelled **Target contract** callout states the closed four-label identity, the two labels that are empty today, and the overhead and `mockpay` rules as planned; the as-built label policy is unchanged. Previously 2026-07-29 — canonical app profiling contract; as-built claims verified against `duynhlab/pkg` and the service repos._
