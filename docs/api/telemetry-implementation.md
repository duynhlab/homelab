# Implement telemetry in a Go service

Wire the shared instrumentation, add the signals that explain your business
operation, then prove their behavior before release. This is a practical guide;
[Application observability](observability.md) and its pillar contracts own the
requirements. Start with [OTel fundamentals](../observability/opentelemetry/fundamentals.md)
if providers, resources or propagation are new to you.

| Task | Result | Rule owner |
|---|---|---|
| Bootstrap and stop | One provider lifecycle per API or worker process | [Shared contract](observability.md), [shutdown](graceful-shutdown.md) |
| Instrument boundaries | HTTP/gRPC/DB children retain the caller context | [Tracing](tracing.md) |
| Explain business behavior | Safe errors, one decision log, meaningful counters | [Logs](logs.md), [metrics](metrics.md), [tracing](tracing.md) |
| Verify delivery | Versioned evidence from tests and the actual environment | [Release gate](../../local-stack/docs/e2e-audit.md), [Kind checklist](../observability/runbooks/telemetry-kind-verification.md) |

## Before editing

Read the service's canonical API contract and its repository instructions. Check
its `go.mod`, the consumed shared-module tags, and the intended image pin. A fix
on `main` is not evidence that a configured image contains it. The
[implementation audit](../observability/audits/2026-10-23-telemetry-implementation.md)
records current gaps; using a shared helper alone does not establish compliance.

The excerpts below use the API surface inspected in `obsx v0.48.0`,
`logger/slogx v0.4.0` and `httpmw v0.4.0` on 2026-10-23. This is example
verification provenance, not a moving fleet version table. Dependency policy
remains in [the shared contract](observability.md#cross-signal-telemetry-standard-rfc-0031--normative).

## 1. Bootstrap each process once

Use `slogx` for the process logger and `obsx.SetupObservability` for providers.
The following is a **bootstrap excerpt**, not a complete `main`: `ctx` is the
startup context and `cfg.Logging.Level` comes from validated service config.
Imports are `context`, `pkg/obsx` and `pkg/logger/slogx` under
`github.com/duynhlab/`.

```go
logger := slogx.New(slogx.Config{Level: cfg.Logging.Level})
slogx.SetDefault(logger)
obs, err := obsx.SetupObservability(ctx, obsx.ConfigFromEnv())
if err != nil {
    logger.Warn(ctx, "Failed to initialize OpenTelemetry", slogx.Err(err))
} else {
    logger = slogx.New(slogx.Config{
        Level: cfg.Logging.Level,
        Flush: obs.ForceFlush,
    })
    slogx.SetDefault(logger)
}
```

Do not add an SDK provider in a service to repair a missing span or metric.
Check the middleware and context first. For Temporal processes, use the
[replay-safe provider factory](observability.md#worker-and-temporal-instrumentation)
at this same bootstrap point. Application readiness does not depend on an
available telemetry backend.

## 2. Install boundary instrumentation

| Boundary | Wiring | What you still own |
|---|---|---|
| Inbound HTTP | `gin.New()` then `httpmw.Tracing`, `Logging`, `Recovery` | Auth/route registration, forwarding request context, shared probe filters |
| Inbound/outbound gRPC | `grpcx` server/client constructors | Pass context and avoid duplicate transport spans |
| Outbound HTTP | `http.Client{Transport: httpmw.Transport(nil), Timeout: ...}` | Bounded timeout, request context and external baggage filtering |
| PostgreSQL | Existing `dbx` construction | Pass the child context; never add SQL arguments or connection secrets to telemetry |
| Worker/activity | `temporalx` integration | Replay-aware workflow signals, activity context and attempt/outcome distinction |
| Profiling | Shared `obsx` setup | Approved identity labels and measured overhead; [profiling contract](profiling.md) |

**HTTP excerpt** after bootstrap; `serviceName` is validated configuration:

```go
r := gin.New()
r.Use(httpmw.Tracing(serviceName))
r.Use(httpmw.Logging(logger.Slog()))
r.Use(httpmw.Recovery(logger.Slog()))
```

Inventory's Backoffice router currently omits tracing and therefore HTTP RED;
its gRPC surface is instrumented. This documented exception is F17 in the audit,
not an example to copy into a new HTTP service.

Build outbound requests with `http.NewRequestWithContext(ctx, ...)`. The current
shared HTTP transport injects baggage from the context; it does **not** enforce
the external-provider allowlist. Review that boundary explicitly (F04).
Asynchronous callbacks need a bounded lifetime and an intentional parent or
span link; replacing the context with `Background()` discards causality.

## 3. Instrument the business decision

Create an INTERNAL span only for meaningful work. Retain the returned context
and pass it to repositories and clients. This **logic excerpt** assumes the
containing function receives `ctx`; use the real package path and operation name:

```go
const scope = "github.com/duynhlab/user-service/internal/logic/v1"
ctx, span := obsx.StartSpan(ctx, scope, "user.profile")
defer span.End()
// Pass ctx, not the original parent context, to the repository call.
```

| Result | Trace | Log | Metric |
|---|---|---|---|
| Success | End the operation span | Log only a useful domain event | Record the defined outcome at its authoritative decision point |
| Expected rejection | Bounded `obsx.RecordOutcome`, status left unchanged | Follow the operation's severity/event contract | Distinguish rejected outcome from infrastructure failure |
| Unexpected failure | `obsx.RecordError` with a safe classified error | Decision boundary owns the application error log | Count the documented failure or attempt, not an invented success |
| Retry/replay | Preserve context; do not create misleading duplicate operations | Avoid adapter + caller duplicate error records | Define attempt versus completion; replay must not increment workflow counters |

**Privacy prerequisite:** `obsx.RecordError` currently bounds text but does not
sanitize it. Do not pass a raw provider response, SQL/driver text, URL containing
credentials or arbitrary wrapped error into it. Use a reviewed safe error class
at the adapter boundary and test the exported event/status values (F02).
Likewise, raw `span.RecordError` does not set Error status (F01).

Use the [metric authoring examples](metrics.md#business-metrics-custom) and
[event catalog](logs.md#event-catalog) instead of copying another service's
names. Before adding a counter, write down exactly what one increment means.
A successful business mutation followed by an idempotency-store failure must
not make a retry count the same completion twice (F03). An SDK counter is not a
transactionally durable accounting ledger.

## 4. Drain, log the stop, then shut down telemetry

Follow [the ordered shutdown contract](graceful-shutdown.md): stop accepting
work, drain servers/workers, close dependencies, emit the process-stop record,
then stop telemetry. Do not give the exporter an already-cancelled signal
context or reuse a depleted HTTP drain deadline.

**Shutdown excerpt** after those steps, using `obs` from bootstrap:

```go
if obs != nil {
    telemetryCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    if err := obs.Shutdown(telemetryCtx); err != nil {
        logger.Error(context.Background(), "OpenTelemetry shutdown error", slogx.Err(err))
    }
}
```

This excerpt also imports `time`. The five-second telemetry budget matches the
inspected main-branch lifecycle fix; configured release tags lag it (F06).
Budget the entire termination sequence against pod grace time. A deadline
argument does not prove every profiler, pool or synchronous stop honors it.
After shutdown, do not expect the error log's OTLP copy to be delivered.

## 5. Prove behavior, then delivery

| Test | Required evidence |
|---|---|
| Real logic under in-memory tracer | Child parent ID, stable scope/name, unexpected Error status, expected outcome |
| Synthetic sensitive provider/driver failure | Secret absent from exported span attributes, events and status, and both log sinks |
| Retry/idempotency recovery | One completion per defined event; explicitly separate attempts |
| Request with synthetic baggage | Incoming/untrusted keys filtered at the intended external boundary |
| HTTP/gRPC/probes | Correct middleware order and correlation; probe filters; no duplicate server spans |
| Temporal history replay | No duplicate workflow logs/metrics; activities retain context |
| Shutdown | Final lifecycle record emitted before shutdown; independent flush budget |

Run the owning service/shared-module tests and blocking policy checks. For a
release, complete the existing Compose API/browser/telemetry gate against the
exact merged SHAs, then verify the pinned images on Kind. A synthetic unit
reproducer, a green import policy, or a populated Grafana panel alone is not a
release qualification. Record expected signals that are absent as failures or
explicitly untested, never as an empty successful query.
