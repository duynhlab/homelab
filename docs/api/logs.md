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

Representative access-log line (middleware-owned summary):

```json
{"level":"info","timestamp":"2026-07-09T02:12:04.455Z","caller":"middleware/logging.go:42","message":"HTTP request","trace_id":"94c290a2e22a985f6f9fa2337e476443","http.request.method":"GET","http.route":"/order/v1/private/orders","http.response.status_code":200,"duration_ms":42}
```

The stdout line above is what `kubectl logs` shows; the same record is also exported over OTLP to VictoriaLogs by the otelzap tee.

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

## Log levels

| Runtime level | Use |
|---------------|-----|
| `debug` | Diagnostic detail; disabled in normal production operation |
| `info` | Normal lifecycle and successful state transitions |
| `warn` | Degraded but handled condition |
| `error` | Operation failed and the final action is return, abandon, or escalation |

`panic` and `fatal` are reserved for unrecoverable bootstrap/process failures
and are not valid `LOG_LEVEL` values. The platform defines no trace log level.

### Kubernetes configuration

**Current state** (`kubernetes/apps/`):

- Fleet-wide: `LOG_LEVEL: "info"`, `LOG_FORMAT: "json"`
- Config validation: `validLogLevels = ["debug", "info", "warn", "error"]`

**Runtime configurability:** `zapx.New(level)` parses and applies `LOG_LEVEL` at startup. The **same level also gates the otelzap tee** — the OTLP bridge is level-gated (`obs.ZapCore(name, minLevel)`) so debug records suppressed on stdout are not exported over OTLP either.

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

Recommended access-log fields:

| Field | Notes |
|-------|-------|
| `http.request.method` | HTTP verb |
| `http.route` | Route template, not raw path with IDs |
| `http.response.status_code` | Final status |
| `duration_ms` or `duration_seconds` | Request latency |
| `rpc.system`, `rpc.service`, `rpc.method` | gRPC access logs |
| `grpc.code` | gRPC status |
| `trace_id` | When span context exists |

**Probe filtering (target contract):** do not emit routine successful health/readiness probe access logs; retain failed probes and readiness state transitions. Verify against the active middleware implementation — see [Application observability § Health filtering](./observability.md#health-readiness-and-reflection-filtering).

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

## Known gaps

| Gap | Impact | Decision | Exit criteria |
|-----|--------|----------|---------------|
| Gin framework plaintext logs | Breaks JSON consistency | Redirect/disable default writer | No `[GIN]` lines in smoke test |
| Pyroscope SDK debug lines | Third-party plaintext noise | Configure SDK or document accepted exception — see [profiling.md](./profiling.md#known-gaps) | No debug line at normal log level |

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

_Last updated: 2026-07-29 — canonical app logging contract._
