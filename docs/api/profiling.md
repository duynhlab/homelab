# Application Profiling

Continuous profiling contract for every Go service and worker in the platform service catalog — `obsx.SetupProfiling`, profile types, environment variables, and trace correlation.

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **Client** | `obsx.SetupProfiling()` (`duynhlab/pkg`), `pyroscope-go` SDK — push every 15s | — |
| **Default** | On in cluster and local-stack (`PROFILING_ENABLED=true`) | — |
| **Correlation** | `pyroscope.profile.id` on spans via `otel-profiling-go` | — |
| **Platform backend** | [Profiling (platform)](../observability/profiling/README.md) — Pyroscope Helm, RustFS, Grafana | — |
| **Cross-cutting** | [Application observability](./observability.md) | — |
| **Design record** | — | None |

---

## Overview

Every Go service pushes pprof data to Pyroscope via the shared **`obsx.SetupProfiling()`** helper — not bespoke profiler code per service. Profiles answer *which line of code* burned CPU or allocated memory during live traffic.

Shared bootstrap and cross-signal label rules: [Application observability](./observability.md).

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
- **Strict helper validation** — empty `PYROSCOPE_ENDPOINT` returns an error; `sync.Once` guards startup.
- Verify exact helper signatures and configuration fields against the active
  `duynhlab/pkg` revision before using the wiring example verbatim.

## Failure, readiness, and shutdown policy

`obsx.SetupProfiling` performs strict configuration validation and returns an
error when profiling cannot be initialized.

Profiling is non-critical to the application data path. Unless a service
contract explicitly records a stricter requirement, the process logs a
sanitized warning and continues without profiling. A profiling failure does
not make application readiness false — core app dependencies still determine
readiness.

Shutdown is bounded:

```go
func initProfiling(
    cfg *config.Config,
    logger *zap.Logger,
) func() {
    if !cfg.Profiling.Enabled {
        return func() {}
    }

    stop, err := obsx.SetupProfiling()
    if err != nil {
        logger.Warn("profiling disabled after setup failure", zap.Error(err))
        return func() {}
    }

    logger.Info("profiling initialized")

    return func() {
        shutdownCtx, cancel := context.WithTimeout(
            context.Background(),
            cfg.ShutdownTimeout,
        )
        defer cancel()

        if err := stop(shutdownCtx); err != nil {
            logger.Warn("profiling shutdown incomplete", zap.Error(err))
        }
    }
}
```

Do not log a profiler URL containing credentials or query secrets at startup.

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
- Mutex/block sampling rates are set by the shared helper; verify against the
  active `pkg/obsx` revision before documenting exact values as as-built.

---

## Trace correlation (app side)

1. **`obsx.TracerProviderWithProfiles`** wraps the OTel `TracerProvider` with `otel-profiling-go` so spans may carry **`pyroscope.profile.id`**.
2. **CPU profiles** may support span-level correlation through profile IDs.
3. **Heap, goroutine, mutex, and block profiles** are commonly service/time scoped — do not promise identical span correlation for every profile type.
4. Correlation behavior depends on the current SDK and Grafana datasource configuration — see [Profiling (platform) § Trace correlation](../observability/profiling/README.md#trace-correlation-platform).

---

## Configuration

On by default. Injected by app ResourceSets and worker manifests:

| Env | Purpose | Default |
|-----|---------|---------|
| `PROFILING_ENABLED` | Toggle | `true` |
| `PYROSCOPE_ENDPOINT` | Pyroscope server | `http://pyroscope.monitoring.svc.cluster.local:4040` |
| `OTEL_SERVICE_NAME` | Identity (`service_name`) | service name |
| `OTEL_RESOURCE_ATTRIBUTES` | Labels (`service.namespace`, `deployment.environment`, `service.version`) | set by ResourceSet |

Set `PROFILING_ENABLED=false` to opt a service out.

Full env table: [Application observability § Environment variables](./observability.md#environment-variables).

### Verification (service side)

1. Check startup log: `profiling initialized` (or warning if disabled after setup failure)
2. Confirm env: `PROFILING_ENABLED=true`, `PYROSCOPE_ENDPOINT` reachable

Backend troubleshooting (Pyroscope pods, RustFS, Grafana datasource): [Profiling (platform) § Troubleshooting](../observability/profiling/README.md#troubleshooting).

---

## Known gaps

| Gap | Impact | Decision | Exit criteria |
|-----|--------|----------|---------------|
| Pyroscope SDK debug lines | Third-party plaintext noise on stdout | Configure SDK log level or document accepted exception | No `[DEBUG] uploading at…` at normal production log level |
| `sync.Once` lifecycle | Complicates tests or multi-mode processes | Document helper lifecycle after pkg review | Test behavior matches intended one-shot init |

Cross-link from logging: [Application logging § Known gaps](./logs.md#known-gaps).

---

## References

- [Application observability](./observability.md)
- [Application tracing](./tracing.md)
- [Profiling (platform)](../observability/profiling/README.md)
- [pyroscope-go SDK](https://github.com/grafana/pyroscope-go)
- [otel-profiling-go](https://github.com/grafana/otel-profiling-go)

_Last updated: 2026-07-29 — canonical app profiling contract._
