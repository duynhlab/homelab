# Application Logging

Structured logging contract for all ten Go microservices and both workers — libraries, JSON shape, levels, and OTLP export via the otelzap tee.

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

**Current status (RFC-0014 P4):**

- The fleet has **converged on `zapx`**: auth migrated off zerolog, cart off clog, joining six services already on zap. One logger, one JSON contract, one tee.
- Every service's zap core is tee'd through an **otelzap** bridge → OTLP → OpenTelemetry Collector → VictoriaLogs (stdout is still emitted for `kubectl logs`).

---

## Fleet status

All ten services and both workers use **`zapx`**. Pre-P4 library migrations:

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

---

## Pod log verification

```bash
# Uniform zapx JSON, with trace_id when a span is active
kubectl logs -n auth deployment/auth --tail=50
kubectl logs -n cart deployment/cart --tail=50
```

### Log output format

Representative line:

```json
{"level":"info","timestamp":"2026-07-09T02:12:04.455Z","caller":"middleware/logging.go:42","message":"HTTP request","trace_id":"94c290a2e22a985f6f9fa2337e476443","method":"GET","path":"/health","status":200,"duration":0.000134,"client_ip":"10.244.1.1","user_agent":"kube-probe/1.33"}
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

**Usage:** `logger.Info("HTTP request", zap.String("method", c.Request.Method), zap.String("path", c.Request.URL.Path))`.

`trace_id`/`span_id` are injected from the OpenTelemetry span context in the logging middleware, so a log line and its trace join on one id.

### Why the fleet converged on `zapx`

Before RFC-0014 P4, three loggers coexisted (zap on six services, clog on cart, zerolog on auth). The otelzap tee needs one uniform zap core. Converging removes field-shape divergence (`msg` vs `message`, Unix vs ISO8601 time).

---

## Log level standards

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

| User Standard | Zap (`zapcore.Level`) |
|----------------|-----------------------|
| panic (5) | PanicLevel (4) |
| fatal (4) | FatalLevel (5) |
| error (3) | ErrorLevel (2) |
| warn (2) | WarnLevel (1) |
| info (1) | InfoLevel (0) |
| debug (0) | DebugLevel (-1) |
| trace (-1) | N/A (zap has no trace level) |

### Kubernetes configuration

**Current state** (`kubernetes/apps/`):

- All 10 services: `LOG_LEVEL: "info"`, `LOG_FORMAT: "json"`
- Config validation: `validLogLevels = ["debug", "info", "warn", "error"]`

**Runtime configurability:** `zapx.New(level)` parses and applies `LOG_LEVEL` at startup. The **same level also gates the otelzap tee** — the OTLP bridge is level-gated (`obs.ZapCore(name, minLevel)`) so debug records suppressed on stdout are not exported over OTLP either.

---

## JSON format requirements

### Required fields

| Field | Description | Notes |
|-------|-------------|-------|
| `timestamp` | Timestamp | ISO8601 (zapx `ISO8601TimeEncoder`) |
| `level` | Log level | Lowercase (`info`, `error`, …) |
| `message` | Log message | Uniform `message` key (was `msg` on clog) |
| `caller` | Source location | `file:line` of the log call |
| `trace_id` | OpenTelemetry Trace ID | Injected when a span is active |
| `span_id` | OpenTelemetry Span ID | When span exists in context |

### OTLP export (app path)

- otelzap maps the zap `message` to the OTLP log body and attaches fields as attributes.
- The Collector's VictoriaLogs exporter sets `VL-Stream-Fields: service.name` (one stream per service) and keeps `trace_id` as a queryable field.

Infra ingest headers (`VL-Msg-Field`, Vector streams) are documented in [Logging (platform)](../observability/logging/README.md#platform-pipeline).

---

## OpenTelemetry integration

- **Tee wiring:** `zapcore.NewTee(stdoutCore, obs.ZapCore(serviceName, minLevel))` — one branch to stdout, one through **otelzap** → OTLP log exporter (`otlploghttp`) → OpenTelemetry Collector.
- **`OTEL_LOGS_ENABLED`** gates the exporter (enabled fleet-wide since RFC-0014 P4). See [Application observability](./observability.md#environment-variables).
- The bridge is **level-gated** to the service's configured level.
- App pods carry `platform.duynhlab.dev/otlp-logs=true` and are **excluded** from Vector — the double-ingest guard. Full pipeline: [Logging (platform)](../observability/logging/README.md).

---

## Known issues

1. **Gin default logger**: Gin's framework logger emits `[GIN] … | 200 | …` plain text, bypassing the structured `zapx` logger. Consider a `gin.DefaultWriter` redirect or custom middleware.
2. **Pyroscope DEBUG**: Plain text `[DEBUG] uploading at...` from the Pyroscope library — third-party, not app-controlled.

---

## Examples

```go
logger.Info("Service starting", zap.String("service", cfg.Service.Name), zap.String("port", cfg.Service.Port))
logger.Info("HTTP request", zap.String("method", c.Request.Method), zap.String("path", c.Request.URL.Path))
```

---

## References

- [Application observability](./observability.md)
- [Logging (platform)](../observability/logging/README.md)
- [RFC-0014: observability standardization](../proposals/rfc/RFC-0014/)

_Last updated: 2026-07-22 — canonical app logging contract; moved from observability/logging/logging-standards.md._
