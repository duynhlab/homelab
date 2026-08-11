# Application Logging

Structured logging contract for every Go service and worker in the platform service catalog — libraries, JSON shape, levels, and OTLP export via the otelzap tee.

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **Logger** | `github.com/duynhlab/pkg/logger/zapx` (fleet-wide since RFC-0014 P4) | — |
| **Format** | JSON on stdout + OTLP logs when `OTEL_LOGS_ENABLED=true` | — |
| **Correlation** | `trace_id` / `span_id` from active span context | — |
| **Platform pipeline** | [Logging (platform)](../observability/logging/README.md) — VictoriaLogs, Vector, dual-path ingest | — |
| **Cross-cutting** | [Application observability](./observability.md) — middleware order, env, `obsx` | — |
| **Design record** | — | [RFC-0014](../proposals/rfc/RFC-0014/) |

---

## Overview

Every service outputs **structured JSON** using the shared **`zapx`** logger. Its zap core is **tee'd** into the OpenTelemetry log pipeline (see [OpenTelemetry integration](#opentelemetry-integration)).

**Current status (RFC-0014 P4):** the fleet has converged on **`zapx`** — one logger, one JSON contract, one otelzap tee → OTLP → OpenTelemetry Collector → VictoriaLogs (stdout is still emitted for `kubectl logs`).

Scope and shared bootstrap rules: [Application observability](./observability.md).

---

## Pod log verification

```bash
# Uniform zapx JSON, with trace_id when a span is active
kubectl logs -n auth deployment/auth --tail=50
kubectl logs -n cart deployment/cart --tail=50
```

### Log output format

Canonical access-log line (middleware-owned summary):

```json
{"level":"info","timestamp":"2026-07-09T02:12:04.455Z","caller":"middleware/logging.go:42","message":"HTTP request","trace_id":"94c290a2e22a985f6f9fa2337e476443","http.request.method":"GET","http.route":"/order/v1/private/orders","http.response.status_code":200,"duration_seconds":0.042}
```

The stdout line is what `kubectl logs` shows; the same record is also exported over OTLP to VictoriaLogs by the otelzap tee.

---

## The `zapx` logger

All services build the logger from the shared adapter (`github.com/duynhlab/pkg/logger/zapx`):

- **JSON encoder** with `TimeKey: "timestamp"` (ISO8601), `MessageKey: "message"`, `LevelKey: "level"`, `CallerKey: "caller"`.
- Level parsed from `LOG_LEVEL` (`debug|info|warn|error`, defaults to `info`).
- `WithContext` / `FromContext` helpers carry a request-scoped logger.

**Setup** (`pkg/logger/zapx/logger.go` in the `duynhlab/pkg` repository):

```go
func New(level string) (*zap.Logger, error) {
    cfg := zap.NewProductionConfig()
    cfg.Level = zap.NewAtomicLevelAt(parseLevel(level))
    cfg.EncoderConfig.TimeKey = "timestamp"
    cfg.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder
    cfg.EncoderConfig.MessageKey = "message"
    cfg.EncoderConfig.LevelKey = "level"
    cfg.EncoderConfig.CallerKey = "caller"
    return cfg.Build()
}
```

`trace_id`/`span_id` are injected from the OpenTelemetry span context in the logging middleware, so a log line and its trace join on one id.

---

## OTel log data model

Every exported record is an OpenTelemetry **LogRecord**. This is the platform
contract for what a log record *is* — the JSON on stdout is a rendering of it,
and the OTLP export carries it natively.

| Field | What it means | Why it matters |
|-------|---------------|----------------|
| `Timestamp` | Time when the event occurred | Builds the incident timeline |
| `ObservedTimestamp` | Time when the collection system observed the event | Identifies parsing or ingestion lag |
| `TraceId` | Trace associated with the log | Enables log-to-trace correlation |
| `SpanId` | Span associated with the log | Pinpoints where in a request the log was emitted |
| `TraceFlags` | W3C trace flags | Preserves trace context and sampling decision |
| `SeverityText` | Original severity label (`INFO`, `ERROR`) | Keeps log levels human-readable |
| `SeverityNumber` | Normalized numeric severity (1–24) | Enables consistent filtering and alerting across languages |
| `Body` | Main log message or structured payload | Stores the core event detail |
| `Resource` | Entity that produced the log (service, pod, namespace) | Supports grouping and ownership |
| `InstrumentationScope` | Library or scope that emitted the log | Debugs instrumentation sources |
| `Attributes` | Additional key-value context | Filtering, grouping, enrichment |

### SeverityNumber ranges

OTel normalizes severity into numeric ranges so backends can filter and alert
without parsing language-specific label strings:

| Range | Meaning | zap level mapped by the otelzap bridge |
|-------|---------|----------------------------------------|
| 1–4 | TRACE | — (zap has no trace level) |
| 5–8 | DEBUG | `DebugLevel` |
| 9–12 | INFO | `InfoLevel` |
| 13–16 | WARN | `WarnLevel` |
| 17–20 | ERROR | `ErrorLevel` |
| 21–24 | FATAL | `FatalLevel` / `PanicLevel` |

### How the platform stack fills the LogRecord

| LogRecord field | Filled by |
|-----------------|-----------|
| `Timestamp` | zap entry time (`zapx` `timestamp`) |
| `ObservedTimestamp` | otelzap bridge / OpenTelemetry Collector at receive time |
| `TraceId`, `SpanId`, `TraceFlags` | `obsx.TraceContext(ctx)` bound to the request logger |
| `SeverityText`, `SeverityNumber` | zap `level` via the otelzap bridge |
| `Body` | zap `message` |
| `Resource` | `pkg/obsx` resource (`service.name`, namespace, pod — from `OTEL_SERVICE_NAME` + Downward API; `service.version` only on the versioned order worker today, ADR-030) |
| `InstrumentationScope` | the scope name passed to `obs.ZapCore(scopeName, minLevel)` |
| `Attributes` | every `zap.Field` on the entry (`caller` included) |

Every field in this mapping is wired by shared code (`pkg/obsx`, `zapx`,
middleware) — a service author only writes `logger.Info(message, fields…)` and
the full LogRecord shape falls out.

---

## Log level standards

Platform severity taxonomy — use when choosing which zap method to call or
interpreting exported JSON `level` values:

| Level Name | Value | Description |
|------------|-------|-------------|
| **panic** | 5 | System crash (unrecoverable error) |
| **fatal** | 4 | System exit (critical error) |
| **error** | 3 | Runtime errors (system continues) |
| **warn** | 2 | Warnings (potential issues) |
| **info** | 1 | Normal operation |
| **debug** | 0 | Detailed debug info |
| **trace** | -1 | Low-level tracing |

### Library level mapping (zap)

The fleet converged on **`zapx`** (RFC-0014 P4) — see
[Migration history](#migration-history). Legacy `pkg/logger/zerolog` and
`pkg/logger/clog` adapters remain in `duynhlab/pkg` but no service imports
them anymore; every API service and worker in the catalog uses `zapx`.

| User Standard | Zap (`zapcore.Level`) |
|----------------|-----------------------|
| panic (5) | PanicLevel (4) |
| fatal (4) | FatalLevel (5) |
| error (3) | ErrorLevel (2) |
| warn (2) | WarnLevel (1) |
| info (1) | InfoLevel (0) |
| debug (0) | DebugLevel (-1) |
| trace (-1) | N/A (zap has no trace level) |

`panic` and `fatal` are **logger methods** (`logger.Panic`, `logger.Fatal`) or
process bootstrap failures — they are **not** valid `LOG_LEVEL` values. The
platform defines no trace log level.

### Runtime configuration (`LOG_LEVEL`)

What operators and config validation actually accept:

| Runtime level | Use |
|---------------|-----|
| `debug` | Diagnostic detail; disabled in normal production operation |
| `info` | Normal lifecycle and successful state transitions |
| `warn` | Degraded but handled condition |
| `error` | Operation failed and the final action is return, abandon, or escalation |

**Kubernetes / service config** (`kubernetes/apps/`, each `*-service/config/config.go`):

- Fleet-wide: `LOG_LEVEL: "info"`, `LOG_FORMAT: "json"`
- Config validation: `validLogLevels = ["debug", "info", "warn", "error"]`

**Wiring contract:**

- stdout logger: `zapx.New(cfg.Logging.Level)` — the validated config value, not a raw env read. `zapx.parseLevel` recognises the four runtime values; anything else defaults to `info`.
- OTLP tee gate: the **same level** gates the export branch — `zapcore.ParseLevel` (fallback `info`) passed to `obs.ZapCore(serviceName, minLevel)` — so debug records suppressed on stdout are not exported over OTLP either.

Legacy adapters (`zerolog`, `clog`) accepted the same four `LOG_LEVEL` strings before P4; only the JSON field shapes differed (`msg` vs `message`, Unix vs ISO8601 time).

---

## Record fields

### Required

| Field | Contract |
|-------|----------|
| `timestamp` | ISO8601 UTC |
| `level` | lowercase supported runtime level |
| `message` | concise human-readable summary |
| `caller` | source location when enabled |

### Conditional

| Field | Present when |
|-------|--------------|
| `trace_id`, `span_id` | a valid active span context exists |
| `event` | the record represents a stable machine-queryable event |
| `operation` | the record belongs to a command/use case |
| `error` / `error.type` | the operation has an error |
| domain/workflow identifiers | operationally justified and permitted by the [common data policy](./observability.md#cross-signal-data-and-privacy-policy) |

### OTLP export (app path)

- otelzap maps the zap `message` to the OTLP log body and attaches fields as attributes.
- The Collector's VictoriaLogs exporter sets `VL-Stream-Fields: service.name` (one stream per service) and keeps `trace_id` as a queryable field.

Infra ingest headers (`VL-Msg-Field`, Vector streams) are documented in [Logging (platform)](../observability/logging/README.md#platform-pipeline).

---

## Event and field naming

- **Message** is stable and concise — not a dump of dynamic IDs.
- Custom field keys use **lower snake_case**.
- Important machine-queryable records carry a stable **`event`** value.
- Do not put IDs into message templates when fields can carry them.
- Do not create one-off aliases such as `orderId`, `order_id`, and `oid` for the same concept.
- Errors use one consistent field shape (`zap.Error(err)` and/or `error.type`).

```go
logger.Info(
    "inventory reservation committed",
    zap.String("event", "inventory.reservation_committed"),
    zap.String("operation", "inventory.commit_reservation"),
    zap.String("reservation_id", reservationID),
)
```

---

## Access-log policy

HTTP and gRPC middleware own **one request/RPC summary record** per call.
Handlers must not also write generic `logger.Info("HTTP request", …)` unless
they are logging a separate domain event.

**Access-log field schema (contract):**

| Field | Notes |
|-------|-------|
| `http.request.method` | HTTP verb |
| `http.route` | Route template, never the raw path with IDs |
| `http.response.status_code` | Final status |
| `duration_seconds` | Request latency, explicit unit |
| `rpc.system`, `rpc.service`, `rpc.method` | gRPC access logs |
| `grpc.code` | gRPC status |
| `trace_id` | When span context exists |

> **Contract target, not yet as-built.** Today every service emits
> `method`/`path`/`status`/`duration`/`client_ip`/`user_agent` on HTTP and
> `method`/`code`/`duration`/`peer` on gRPC (see
> [tracing.md](./tracing.md) for the fields recorded today, and
> [api.md](./api.md) for the probe-filtering gap). The rename to this schema —
> and dropping `client_ip`/`user_agent` per the
> [data policy](./observability.md#cross-signal-data-and-privacy-policy) — is
> the LOG-1 refactor.

Level policy: HTTP logs `error` for status ≥ 500, `warn` for 400–499, else
`info` — a rejected request is not a broken service. gRPC follows
the **status-code class** (pkg ≥ v0.31.0, verbatim from go-grpc-middleware's
`DefaultServerCodeToLevel`): caller-attributable outcomes at `info`
(`OK`, `NotFound`, `Canceled`, `AlreadyExists`, `InvalidArgument`,
`Unauthenticated`), degraded-but-explicable at `warn` (`DeadlineExceeded`,
`PermissionDenied`, `ResourceExhausted`, `FailedPrecondition`, `Aborted`,
`OutOfRange`, `Unavailable`), faults at `error` (`Unknown`, `Unimplemented`,
`Internal`, `DataLoss`; unknown codes default to `error`). This is as-built:
every service pins `pkg/grpcx v0.36.1`. HTTP messages are `HTTP request`, gRPC
messages are `gRPC request`.

**Probe filtering (contract):** no routine successful health/readiness probe
access logs on either transport; keep failed probes and readiness state
transitions. gRPC enforces this in the `pkg/grpcx` access interceptor
(`grpc.health.v1.Health` + reflection skipped); the HTTP logging middleware
applies the same skip list as `TracingMiddleware`. Signal matrix:
[Application observability § Health filtering](./observability.md#health-readiness-and-reflection-filtering).

---

## Error logging ownership

Lower layers return typed errors. The boundary that decides return, retry,
compensate, abandon, or escalate owns the **error** log. Access middleware owns
the final request/RPC summary.

Full rules: [Application observability § Error ownership](./observability.md#error-ownership).

---

## Data safety

Never log passwords, password hashes, tokens, cookies, authorization headers,
payment secrets, PAN-like data, raw bodies, unredacted signatures, or
connection strings containing credentials. Email, phone, address, IP, and full
User-Agent values are omitted or redacted by default.

Business identifiers may be logged when operationally necessary; they are
high-cardinality and may be pseudonymous data. See the
[cross-signal data policy](./observability.md#cross-signal-data-and-privacy-policy).

---

## OpenTelemetry integration

- **Tee wiring:** `zapcore.NewTee(stdoutCore, obs.ZapCore(serviceName, minLevel))` — one branch to stdout, one through **otelzap** → OTLP log exporter (`otlploghttp`) → OpenTelemetry Collector.
- **`OTEL_LOGS_ENABLED`** gates the exporter (enabled fleet-wide since RFC-0014 P4). See [Application observability](./observability.md#environment-variables).
- The bridge is **level-gated** to the service's configured level.
- App pods carry `platform.duynhlab.dev/otlp-logs=true` and are **excluded** from Vector — the double-ingest guard. Full pipeline: [Logging (platform)](../observability/logging/README.md).

---

## Examples

```go
logger.Info(
    "service started",
    zap.String("event", "service.started"),
    zap.String("listen_address", cfg.ListenAddress),
)

logger.Warn(
    "dependency call degraded",
    zap.String("event", "dependency.degraded"),
    zap.String("dependency", "review"),
    zap.String("operation", "product.get_details"),
    zap.Error(err),
)
```

Do not log collector or Pyroscope endpoints when they could contain embedded credentials.

---

## Migration history

Pre-P4 library migrations (RFC-0014 P4 converged the fleet on `zapx`):

| Service | Logger | Was |
|---------|--------|-----|
| **auth** | zapx | zerolog |
| **cart** | zapx | clog |
| **product** | zapx | zap (reference impl) |
| **order** | zapx | zap |
| **review** | zapx | zap |
| **notification** | zapx | zap |
| **shipping** | zapx | zap |
| **user** | zapx | zap |
| **payment** | zapx | zap |
| **checkout** | zapx | zap |

Before RFC-0014 P4, three loggers coexisted (zap, clog, zerolog). The otelzap tee needs one uniform zap core. Converging removes field-shape divergence (`msg` vs `message`, Unix vs ISO8601 time).

---

## References

- [Application observability](./observability.md)
- [Logging (platform)](../observability/logging/README.md)
- [RFC-0014: observability standardization](../proposals/rfc/RFC-0014/)

_Last updated: 2026-08-11 — HTTP level policy is 500→error / 400–499→warn, and the status-class gRPC mapping is as-built on `pkg/grpcx v0.36.1`._
