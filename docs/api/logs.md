# Logging Standards

> **Document Status:** Production  
> **Last Updated:** 2026-01-31  
> **Integration:** VictoriaLogs + OpenTelemetry

---

## Overview

This document defines centralized logging standards for all microservices. All services must output **JSON format** logs for compatibility with VictoriaLogs and OpenTelemetry tracing.

**Current status:**
- **2 services**: cart (clog), auth (zerolog)
- **6 services**: product, order, review, notification, shipping, user (Zap)
- No migration planned - both approaches coexist

---

## Microservices Logging Status

| Service | Library | Notes |
|---------|---------|-------|
| **cart** | clog (slog wrapper) | Context-first API, zero dependencies |
| **auth** | zerolog | Chainable API, zero-allocation JSON |
| **product** | zap | Primary logger |
| **order** | zap | Primary logger |
| **review** | zap | Primary logger |
| **notification** | zap | Primary logger |
| **shipping** | zap | Primary logger |
| **user** | zap | Primary logger |

---

## Pod Log Verification

Verify cart/auth service logs in Kubernetes:

```bash
# Verify cart (clog) logs - JSON format, trace_id
kubectl logs -n cart deployment/cart --tail=50

# Verify auth (zerolog) logs - JSON format, trace_id
kubectl logs -n auth deployment/auth --tail=50
```

### Log Output Analysis (Verified)

**Cart (clog) sample output:**
```json
{"time":"2026-01-31T02:12:04.4558351Z","level":"INFO","msg":"HTTP request","trace_id":"94c290a2e22a985f6f9fa2337e476443","method":"GET","path":"/health","status":200,"duration":134284,"client_ip":"10.244.1.1","user_agent":"kube-probe/1.33"}
```

**Auth (zerolog) sample output:**
```json
{"level":"info","trace_id":"a2ca3d67166eb58ba9917d91032e5d44","method":"GET","path":"/health","status":200,"duration":0.086978,"client_ip":"10.244.2.1","user_agent":"kube-probe/1.33","time":1769825539,"message":"HTTP request"}
```

**Findings:**

| Aspect | Cart (clog) | Auth (zerolog) | Standardization |
|--------|-------------|----------------|-----------------|
| **time** | ISO8601 | Unix | Prefer ISO8601 for VictoriaLogs |
| **level** | Uppercase `INFO` | Lowercase `info` | Document preferred format |
| **message field** | `msg` | `message` | Vector uses `VL-Msg-Field: message,msg` |
| **trace_id** | Present | Present | OK |
| **span_id** | Not in HTTP logs | Not in HTTP logs | OK (appears when span exists) |
| **duration** | Integer (nanoseconds) | Float (seconds) | Consider standardizing unit |

---

## Available Logging Libraries

### Zap (`go.uber.org/zap`)

- **Current Usage**: 6 services (product, order, review, notification, shipping, user)
- **Status**: Primary logger for majority of services
- **Features**: High performance, structured logging
- **Tracing**: Manual implementation required
- **Dependencies**: ~10 packages

### clog (`github.com/chainguard-dev/clog`)

- **Current Usage**: 1 service (cart)
- **Base**: Wrapper for `log/slog` (Go 1.21+ standard library)
- **Features**: Zero dependencies, context-first API, native JSON support
- **Tracing**: Easy integration via Handler middleware
- **Dependencies**: 0 (uses stdlib)

### zerolog (`github.com/rs/zerolog`)

- **Current Usage**: 1 service (auth)
- **Features**: Zero-allocation JSON logger, chainable API
- **Tracing**: Native support
- **Dependencies**: ~3 packages

---

## Library Comparison

| Feature | Zap | clog (slog wrapper) | Zerolog |
|---------|-----|----------------------|---------|
| **JSON Output** | High performance | Native | High performance |
| **Tracing Support** | Manual (fields) | Easy with Handler | Native support |
| **API Style** | Fluent / Type-safe | Printf / KV | Chainable |
| **Context Propagation** | Manual wrapper | Built-in | Built-in |
| **Dependencies** | ~10 | 0 (stdlib) | ~3 |
| **Usage** | 6 services | cart | auth |

---

## Selection Reasons

### Why clog (cart)?

- Zero dependencies (uses Go stdlib)
- Context-first API (`clog.FromContext(ctx)`)
- Native JSON support via `slog.JSONHandler`
- Cloud-native design (Kubernetes, GCP)
- Easy OpenTelemetry integration via Handler middleware
- Future-proof (Go standard library)

### Why zerolog (auth)?

- Zero-allocation JSON logging
- Chainable API (developer-friendly)
- Native tracing support
- High performance
- Simple API

### Zap (6 services)

- Primary logger for product, order, review, notification, shipping, user
- Manual tracing integration required
- More dependencies than clog/zerolog

---

## Deep Dives

### clog (slog wrapper) Implementation

**Architecture:** Wrapper over `log/slog` with custom `TracingHandler`.

**Setup** (`pkg/logger/clog/logger.go` in the `duynhne/pkg` repository):
```go
func Setup(level string) {
    slogLevel := parseSlogLevel(level)  // debug, info, warn, error from LOG_LEVEL
    handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
        Level: slogLevel,
    })
    logger := slog.New(&TracingHandler{handler: handler})
    slog.SetDefault(logger)
}
```

**TracingHandler** injects `trace_id` and `span_id` from OpenTelemetry context:
```go
func (h *TracingHandler) Handle(ctx context.Context, r slog.Record) error {
    if span := trace.SpanFromContext(ctx); span.SpanContext().IsValid() {
        r.AddAttrs(
            slog.String("trace_id", span.SpanContext().TraceID().String()),
            slog.String("span_id", span.SpanContext().SpanID().String()),
        )
    }
    return h.handler.Handle(ctx, r)
}
```

**Usage:** `clog.InfoContext(ctx, "message", "key", value)` or `slog.Info("message", "key", value)`

### zerolog Implementation

**Architecture:** Pure Go, zero-allocation design.

**Setup** (`pkg/logger/zerolog/logger.go` in the `duynhne/pkg` repository):
```go
func Setup(level string) {
    zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
    zerolog.SetGlobalLevel(parseZerologLevel(level))  // debug, info, warn, error from LOG_LEVEL
    log.Logger = zerolog.New(os.Stdout).With().Timestamp().Logger()
}
```

**Context with trace:** `WithContext(ctx)` creates sub-logger with `trace_id` and `span_id` when span exists.

**Usage:** `log.Info().Str("key", "value").Msg("message")`

### Zap Implementation

**Current patterns:** 6 services use Zap with JSON encoder. Configuration in `middleware/logging.go`:
- `TimeKey`: "timestamp"
- `MessageKey`: "message"
- `LevelKey`: "level"
- Manual trace_id injection in logging middleware

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

| User Standard | Zap | clog (slog) | zerolog |
|----------------|-----|--------------|---------|
| panic (5) | PanicLevel (4) | N/A (Error+panic) | PanicLevel (5) |
| fatal (4) | FatalLevel (5) | N/A (Error+exit) | FatalLevel (4) |
| error (3) | ErrorLevel (2) | LevelError (8) | ErrorLevel (3) |
| warn (2) | WarnLevel (1) | LevelWarn (4) | WarnLevel (2) |
| info (1) | InfoLevel (0) | LevelInfo (0) | InfoLevel (1) |
| debug (0) | DebugLevel (-1) | LevelDebug (-4) | DebugLevel (0) |
| trace (-1) | N/A | Custom (-8) | TraceLevel (-1) |

**Notes:** slog does not have panic/fatal levels by design. Use Error + panic() or Error + os.Exit().

### Kubernetes Configuration

**Current state** (`kubernetes/apps/`):
- All 8 services: `LOG_LEVEL: "info"`, `LOG_FORMAT: "json"`
- Config validation: `validLogLevels = ["debug", "info", "warn", "error"]`

**Runtime configurability:** clog and zerolog `Setup(level string)` now parse and apply `LOG_LEVEL` from config. Cart and auth pass `cfg.Logging.Level` to `Setup()` at startup.

---

## JSON Format Requirements

### Required Fields

| Field | Description | Notes |
|-------|-------------|-------|
| `time` | Timestamp | ISO8601 preferred; zerolog defaults to Unix |
| `level` | Log level | INFO/info both observed |
| `msg` or `message` | Log message | clog uses `msg`, zerolog uses `message` |
| `trace_id` | OpenTelemetry Trace ID | Automatically injected - verified in cart and auth |
| `span_id` | OpenTelemetry Span ID | When span exists in context |

### VictoriaLogs Compatibility

- **VL-Msg-Field**: Use `message,msg` (comma-separated) to support both clog and zerolog
- **VL-Time-Field**: Use `time` - both ISO8601 and Unix parseable
- **Field naming**: clog outputs `msg`, zerolog outputs `message`

---

## Service Logging Summary

- **2 services**: cart (clog), auth (zerolog)
- **6 services**: product, order, review, notification, shipping, user (Zap)
- No migration planned - both approaches coexist

---

## Integration with Observability Stack

### VictoriaLogs Integration

- Log ingestion via Vector
- Field mapping: `VL-Msg-Field: message,msg` (support cart and auth)
- Stream fields configuration

### OpenTelemetry Integration

- Automatic trace_id injection (verified in both cart and auth)
- span_id when span exists in context
- Context propagation
- Correlation with traces

---

## Known Issues

1. **Gin default logger**: Both cart and auth output `[GIN] 2026/01/31 - 02:12:04 | 200 | ...` plain text. Gin framework uses its own logger, not structured logger. Consider `gin.DefaultWriter` redirect or custom middleware.

2. **Pyroscope DEBUG**: Plain text `[DEBUG] uploading at...` from Pyroscope library - third-party, not app-controlled.

3. **Field inconsistency**: Document `msg` vs `message` and time format. Vector uses `VL-Msg-Field: message,msg` to support both.

---

## Examples

### clog (cart)
```go
slog.Info("Service starting", "service", cfg.Service.Name, "port", cfg.Service.Port)
clog.InfoContext(ctx, "HTTP request", "method", c.Request.Method, "path", c.Request.URL.Path)
```

### zerolog (auth)
```go
log.Info().Str("service", cfg.Service.Name).Str("port", cfg.Service.Port).Msg("Service starting")
log.Info().Str("method", c.Request.Method).Str("path", c.Request.URL.Path).Msg("HTTP request")
```

### Zap (6 services)
```go
logger.Info("Service starting", zap.String("service", cfg.Service.Name), zap.String("port", cfg.Service.Port))
logger.Info("HTTP request", zap.String("method", c.Request.Method), zap.String("path", c.Request.URL.Path))
```

---

## References

- [specs/active/context-aware-logging/research.md](../../specs/active/context-aware-logging/research.md) - Library comparison and deep dives
- [specs/active/context-aware-logging/victorialogs-vector-research.md](../../specs/active/context-aware-logging/victorialogs-vector-research.md) - VictoriaLogs integration
- [docs/observability/logging/README.md](../observability/logging/README.md) - Structured logging guide (Zap-focused)
