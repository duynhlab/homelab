# Logging Standards

> **Document Status:** Production  
> **Last Updated:** 2026-07-09  
> **Integration:** VictoriaLogs + OpenTelemetry (otelzap → OTLP)

---

## Overview

This document defines centralized logging standards for all microservices. Every
service outputs **structured JSON** using the shared **`zapx`** logger, and its
zap core is **tee'd** into the OpenTelemetry log pipeline (see
[OpenTelemetry Integration](#opentelemetry-integration)).

> This is the **implementation & standards** doc (how a service logs). For the
> logging **pipeline architecture**, why-this-stack rationale, and scaling, see
> [observability → logging](README.md).

**Current status (RFC-0014 P4):**
- The fleet has **converged on `zapx`** (`github.com/duynhlab/pkg/logger/zapx`):
  **auth** migrated off zerolog and **cart** off clog, joining the six services
  already on zap. One logger, one JSON contract, one tee.
- Every service's zap core is tee'd through an **otelzap** bridge → OTLP →
  OpenTelemetry Collector → VictoriaLogs (stdout is still emitted for
  `kubectl logs`).

---

## Microservices Logging Status

All services use the shared **`zapx`** adapter; the "Was" column records the
pre-P4 library each replaced.

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

---

## Pod Log Verification

Verify service logs in Kubernetes (same command and format for every service —
substitute the namespace/deployment):

```bash
# Uniform zapx JSON, with trace_id when a span is active
kubectl logs -n auth deployment/auth --tail=50
kubectl logs -n cart deployment/cart --tail=50
```

### Log Output Format

Every service emits the same `zapx` JSON shape — ISO8601 `timestamp`, lowercase
`level`, `message`, and `caller` keys — with `trace_id`/`span_id` present when a
span is active. Representative line:

```json
{"level":"info","timestamp":"2026-07-09T02:12:04.455Z","caller":"middleware/logging.go:42","message":"HTTP request","trace_id":"94c290a2e22a985f6f9fa2337e476443","method":"GET","path":"/health","status":200,"duration":0.000134,"client_ip":"10.244.1.1","user_agent":"kube-probe/1.33"}
```

Because the format is now uniform, the pre-P4 `msg`-vs-`message` and
ISO8601-vs-Unix inconsistencies (cart on clog, auth on zerolog) are gone. The
stdout line above is what `kubectl logs` shows; the same record is also exported
over OTLP to VictoriaLogs by the otelzap tee.

---

## The `zapx` logger

All services build the logger from the shared adapter
(`github.com/duynhlab/pkg/logger/zapx`), which centralizes the production zap
configuration the zap-based services previously duplicated in each
`middleware/logging.go`:

- **JSON encoder** with `TimeKey: "timestamp"` (ISO8601), `MessageKey: "message"`,
  `LevelKey: "level"`, `CallerKey: "caller"`.
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

`trace_id`/`span_id` are injected from the OpenTelemetry span context in the
logging middleware, so a log line and its trace join on one id.

### Why the fleet converged on `zapx`

Before RFC-0014 P4, three loggers coexisted (zap on six services, clog on cart,
zerolog on auth). The otelzap tee (below) needs one uniform zap core, so auth and
cart were migrated onto `zapx`. Converging also removes the field-shape
divergence (`msg` vs `message`, Unix vs ISO8601 time) that previously forced
`VL-Msg-Field: message,msg` workarounds in the ingest path.

---

## Log Level Standards

We follow a standardized log level schema (aligned with Syslog/Zerolog):

| Level Name | Value | Description |
|------------|-------|-------------|
| **panic** | 5 | System crash (unrecoverable error) |
| **fatal** | 4 | System exit (critical error) |
| **error** | 3 | Runtime errors (system continues) |
| **warn** | 2 | Warnings (potential issues) |
| **info** | 1 | Normal operation |
| **debug** | 0 | Detailed debug info |
| **trace** | -1 | Low-level tracing |

### Library Level Mapping

The fleet is uniformly on zap, so the mapping is single-column:

| User Standard | Zap (`zapcore.Level`) |
|----------------|-----------------------|
| panic (5) | PanicLevel (4) |
| fatal (4) | FatalLevel (5) |
| error (3) | ErrorLevel (2) |
| warn (2) | WarnLevel (1) |
| info (1) | InfoLevel (0) |
| debug (0) | DebugLevel (-1) |
| trace (-1) | N/A (zap has no trace level) |

### Kubernetes Configuration

**Current state** (`kubernetes/apps/`):
- All 10 services: `LOG_LEVEL: "info"`, `LOG_FORMAT: "json"`
- Config validation: `validLogLevels = ["debug", "info", "warn", "error"]`

**Runtime configurability:** `zapx.New(level)` parses and applies `LOG_LEVEL` at
startup for every service. The **same level also gates the otelzap tee** — the
OTLP bridge is level-gated (`obs.ZapCore(name, minLevel)`) so debug records that
never reach the stdout core are not silently exported over OTLP either.

---

## JSON Format Requirements

### Required Fields

| Field | Description | Notes |
|-------|-------------|-------|
| `timestamp` | Timestamp | ISO8601 (zapx `ISO8601TimeEncoder`) |
| `level` | Log level | Lowercase (`info`, `error`, …) |
| `message` | Log message | Uniform `message` key (was `msg` on clog) |
| `caller` | Source location | `file:line` of the log call |
| `trace_id` | OpenTelemetry Trace ID | Injected when a span is active |
| `span_id` | OpenTelemetry Span ID | When span exists in context |

### VictoriaLogs Compatibility

- **App path (OTLP):** otelzap maps the zap `message` to the OTLP log body and
  attaches fields as attributes; the Collector's VictoriaLogs exporter sets
  `VL-Stream-Fields: service.name` (one stream per service) and keeps `trace_id`
  as a queryable field.
- **Infra path (Vector jsonline):** `VL-Msg-Field: message`, `VL-Time-Field: timestamp`.
  Vector's `VL-Msg-Field: message,msg` fallback remains only for non-app sources
  that may still emit `msg`.

---

## Service Logging Summary

- **All 10 services + both workers**: converged on **`zapx`** (auth off zerolog,
  cart off clog, six already on zap) — one JSON contract, one otelzap tee.

---

## Integration with Observability Stack

Logs reach VictoriaLogs by **two complementary paths** (see the
[logging hub](README.md) for the full picture): app services over **OTLP**, and
non-instrumented workloads via **Vector**.

### VictoriaLogs Integration

- **App logs — OTLP.** The `zapx` core is tee'd
  (`zapcore.NewTee(stdoutCore, obs.ZapCore(serviceName, minLevel))`): one branch
  writes stdout for `kubectl logs`, the other bridges through **otelzap** → OTLP
  log exporter (`otlploghttp`) → OpenTelemetry Collector → VictoriaLogs' OTLP
  ingest (`/insert/opentelemetry/v1/logs`). The exporter header
  `VL-Stream-Fields: service.name` yields one stream per service.
- **Infra logs — Vector.** Databases, Kong's access log, the frontend, and system
  pods are tailed by the single Vector DaemonSet and shipped over `/insert/jsonline`.
  App pods carry `platform.duynhlab.dev/otlp-logs=true` and are **excluded** from
  Vector — the double-ingest guard.

### OpenTelemetry Integration

- **otelzap tee → OTLP-logs export.** Application logs are exported over OTLP
  alongside traces and metrics; `OTEL_LOGS_ENABLED` gates the exporter (enabled
  fleet-wide since RFC-0014 P4).
- The bridge is **level-gated** to the service's configured level, so debug
  records suppressed on stdout are not exported over OTLP either.
- `trace_id`/`span_id` are injected from the span context; `trace_id` is a
  first-class queryable field in VictoriaLogs, correlating logs with traces.

---

## Known Issues

1. **Gin default logger**: Gin's framework logger emits `[GIN] … | 200 | …` plain
   text, bypassing the structured `zapx` logger. Consider a `gin.DefaultWriter`
   redirect or custom middleware.

2. **Pyroscope DEBUG**: Plain text `[DEBUG] uploading at...` from the Pyroscope
   library — third-party, not app-controlled.

---

## Examples

Uniform `zapx` usage across all services:

```go
logger.Info("Service starting", zap.String("service", cfg.Service.Name), zap.String("port", cfg.Service.Port))
logger.Info("HTTP request", zap.String("method", c.Request.Method), zap.String("path", c.Request.URL.Path))
```

---

_Last updated: 2026-07-14 — fleet converged on `zapx` (auth off zerolog, cart off clog); otelzap tee → OTLP-logs export (fleet-wide since RFC-0014 P4); dual-path ingest (app OTLP + Vector infra) into VictoriaLogs._
