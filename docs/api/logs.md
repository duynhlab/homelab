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

Representative access-log line (middleware-owned summary, as emitted today):

```json
{"level":"info","timestamp":"2026-07-09T02:12:04.455Z","caller":"middleware/logging.go:42","message":"HTTP request","trace_id":"94c290a2e22a985f6f9fa2337e476443","method":"GET","path":"/health","status":200,"duration":0.000134,"client_ip":"10.244.1.1","user_agent":"kube-probe/1.33"}
```

The stdout line above is what `kubectl logs` shows; the same record is also exported over OTLP to VictoriaLogs by the otelzap tee. `duration` is a zap `Duration` field rendered with the production default encoder — a float of **seconds**. Note the `/health` probe line: HTTP access logs are not probe-filtered today (see [Access-log policy](#access-log-policy)).

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
them anymore; all ten API services and workers use `zapx`.

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

**Wiring (verified 2026-07-29 against `duynhlab/pkg` and every service `cmd/main.go`):**

- stdout logger: `zapx.New(level)` — `zapx.parseLevel` recognises the four runtime values; anything else defaults to `info`. auth and cart pass `cfg.Logging.Level`; the other eight services pass `os.Getenv("LOG_LEVEL")` directly (same value, but bypasses config — see [Known gaps](#known-gaps)).
- OTLP tee gate: every service computes `minLevel` via `zapcore.ParseLevel(os.Getenv("LOG_LEVEL"))` (fallback `info`) and passes it to `obs.ZapCore(serviceName, minLevel)` — debug records suppressed on stdout are not exported over OTLP either.

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

**As-built fields (verified 2026-07-29):**

| Signal | Message | Fields |
|--------|---------|--------|
| HTTP (per-service `middleware/logging.go`) | `HTTP request` | `trace_id`, `method`, `path`, `status`, `duration` (seconds float), `client_ip`, `user_agent`; level `error` when status ≥ 400, else `info` |
| gRPC (`pkg/grpcx` access interceptor) | `gRPC request` | `trace_id`, `method`, `code`, `duration`, `peer`; level `error` for any non-OK code |

**Target access-log schema (planned — not emitted today):** semconv-shaped keys
`http.request.method`, `http.route` (route template, not raw path),
`http.response.status_code`, an explicit-unit latency field
(`duration_seconds`), `rpc.system`/`rpc.service`/`rpc.method`, `grpc.code`.
Adopting it is a fleet-wide middleware change tracked in [Known gaps](#known-gaps).

**Probe filtering (as-built):** the gRPC access interceptor skips
`grpc.health.v1.Health` and reflection RPCs. HTTP access logs have **no** probe
filter — every kube-probe hit logs one `info` line today. Target: drop routine
successful probe lines, keep failed probes and readiness transitions. Signal
matrix: [Application observability § Health filtering](./observability.md#health-readiness-and-reflection-filtering).

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
| HTTP access logs not probe-filtered | One `info` line per kube-probe hit, per pod | Add a skip list to the HTTP logging middleware (keep failed probes) | No routine `/health`/`/ready` 2xx lines in smoke test |
| Access-log field names are pre-semconv (`method`/`path`/`status`) | Diverges from the target semconv schema above | Fleet-wide middleware rename, one release | Emitted fields match the target schema |
| Eight services build the logger from `os.Getenv("LOG_LEVEL")`, not `cfg.Logging.Level` | Logger exists before config validation; invalid level silently becomes `info` | Unify on `cfg.Logging.Level` (auth/cart pattern) | All ten `cmd/main.go` pass the config value |
| auth-service OTLP branch lacks native trace correlation | Its logging middleware binds only the string `trace_id`, never `obsx.TraceContext`, so exported records carry no OTLP trace/span IDs | Align with the order/product pattern | auth OTLP records join traces in VictoriaLogs |

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

_Last updated: 2026-07-29 — canonical app logging contract; as-built claims verified against `duynhlab/pkg` and the service repos._
