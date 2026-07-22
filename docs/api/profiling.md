# Application Profiling

Continuous profiling contract for all ten Go microservices and both workers — `obsx.SetupProfiling`, profile types, environment variables, and trace correlation.

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
- **Fail-closed & idempotent** — empty `PYROSCOPE_ENDPOINT` returns error; `sync.Once` guards startup; shutdown func flushes on exit.

### Per-service wiring

Every service and worker uses the same gate in `cmd/main.go`:

```go
func initProfiling(cfg *config.Config, logger *zap.Logger) func() {
    if !cfg.Profiling.Enabled {            // PROFILING_ENABLED=false
        return func() {}
    }
    stop, err := obsx.SetupProfiling()
    if err != nil {
        logger.Warn("Failed to initialize profiling", zap.Error(err))
        return func() {}
    }
    logger.Info("Profiling initialized", zap.String("endpoint", cfg.Profiling.Endpoint))
    return func() { _ = stop(context.Background()) }
}
```

Profiling is a config flag, not bespoke instrumentation code.

---

## Trace correlation (app side)

1. **`obsx.TracerProviderWithProfiles`** wraps the OTel `TracerProvider` with `otel-profiling-go` so spans carry **`pyroscope.profile.id`** (CPU profiles are span-scoped; heap/goroutine/mutex/block are service-scoped).
2. Grafana **Profiles for this span** uses the datasource link configured in platform manifests — see [Profiling (platform)](../observability/profiling/README.md#trace-correlation-platform).

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

1. Check startup log: `Profiling initialized`
2. Confirm env: `PROFILING_ENABLED=true`, `PYROSCOPE_ENDPOINT` reachable

Backend troubleshooting (Pyroscope pods, RustFS, Grafana datasource): [Profiling (platform) § Troubleshooting](../observability/profiling/README.md#troubleshooting).

---

## References

- [Application observability](./observability.md)
- [Application tracing](./tracing.md)
- [Profiling (platform)](../observability/profiling/README.md)
- [pyroscope-go SDK](https://github.com/grafana/pyroscope-go)
- [otel-profiling-go](https://github.com/grafana/otel-profiling-go)

_Last updated: 2026-07-22 — canonical app profiling contract._
