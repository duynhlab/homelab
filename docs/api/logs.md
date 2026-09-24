# Application Logging

Structured logging contract for every Go service and worker in the platform service catalog — libraries, JSON shape, levels, and OTLP export via the otelzap tee.

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **Logger** | `github.com/duynhlab/pkg/logger/zapx` (fleet-wide since RFC-0014 P4) | — |
| **Format** | JSON on stdout + OTLP logs when `OTEL_LOGS_ENABLED=true` | — |
| **Correlation** | `trace_id` / `span_id` from active span context | — |
| **Platform pipeline** | [Logging (platform)](../observability/logging/README.md) — dual-path ingest (OTLP + Vector) into **two** stores: VictoriaLogs (7d, LogsQL) and ClickHouse `otel_logs` (90d, SQL) | — |
| **Cross-cutting** | [Application observability](./observability.md) — middleware order, env, `obsx` | — |
| **Design record** | — | [RFC-0014](../proposals/rfc/RFC-0014/) · **[RFC-0031](../proposals/rfc/RFC-0031/) (Accepted 2026-09-17, not yet as-built)** → [ADR-070](../proposals/adr/ADR-070-logging-facade-and-event-catalog/) (slog facade, event catalog) · [ADR-071](../proposals/adr/ADR-071-telemetry-event-data-contract/) (access/event schema, privacy) |

---

## Overview

Every service outputs **structured JSON** using the shared **`zapx`** logger. Its zap core is **tee'd** into the OpenTelemetry log pipeline (see [OpenTelemetry integration](#opentelemetry-integration)).

**Current status (RFC-0014 P4):** the fleet has converged on **`zapx`** — one logger, one
JSON contract, one otelzap tee → OTLP → OpenTelemetry Collector, which exports to **two**
stores: **VictoriaLogs** (7-day ops retention, LogsQL) and **ClickHouse** `otel_logs`
(90-day SQL, [ADR-023](../proposals/adr/ADR-023-clickhouse-observability-olap/)). Stdout is
still emitted for `kubectl logs`.

Scope and shared bootstrap rules: [Application observability](./observability.md).

> **Target contract — RFC-0031, `Accepted` 2026-09-17. The facade now exists
> (`logger/slogx` v0.1.0, tagged 2026-09-23); no service has adopted it, so every
> section below still describes `zapx` as deployed.** The fleet
> logger becomes **`pkg/logger/slogx`** — a context-first facade over the standard
> library's `slog` that redacts once and renders the same record to stdout and OTLP;
> `zapx` and the otelzap tee are retired in the same release train, and no service may
> import `zap`, `zapcore`, `log/slog` directly, `zerolog` or an OTel log bridge
> ([ADR-070](../proposals/adr/ADR-070-logging-facade-and-event-catalog/) (slog facade, event catalog)). The access record moves to the semconv keys shown in
> [§ Log output format](#log-output-format) and drops raw path, `client_ip` and
> `user_agent`; named events form a five-class catalog with a fixed grammar and one
> deny list applied before every sink ([ADR-071](../proposals/adr/ADR-071-telemetry-event-data-contract/) (access/event schema, privacy)). Every section below still describes
> **`zapx` as deployed**; it is rewritten to as-built when RFC-0031 Phase 3 lands. New
> logging code is reviewed against the target rules from this date — see
> [observability.md § Cross-signal telemetry standard](./observability.md#cross-signal-telemetry-standard-rfc-0031--normative-planned).
>
> **What v0.1.0 fixes about the envelope, and the one query that breaks.** The six
> envelope keys are byte-for-byte what `zapx` emits, so stored queries on
> `timestamp`, `level`, `message`, `caller`, `trace_id` and `span_id` survive the
> cutover untouched — and they are now *reserved*, so a service attribute can no
> longer collide with one. The error field does change: `zap.Error(err)` wrote a
> single string field `error`; `slogx.Err(err)` writes two flat fields, `error.type`
> (the Go type, the low-cardinality label ADR-075 also puts on the span) and
> `error.message` (the text, redacted and bounded). **Any dashboard panel, alert
> expression or saved LogsQL filter matching `error` as a string must move to
> `error.message`, or better to `error.type`, before the first service cuts over.**
> Two levels join the four: `trace` (severity 1) and `fatal` (21); on OTLP the
> severity *number* is the field to filter, because the bridge writes severity text
> with the standard library's spelling, which has no name for those two.

---

## Pod log verification

```bash
# Uniform zapx JSON, with trace_id when a span is active
kubectl logs -n auth deployment/auth --tail=50
kubectl logs -n cart deployment/cart --tail=50
```

### Log output format

Canonical access-log line (middleware-owned summary) — **the contract target, not
yet what the fleet emits**; see [Access-log policy](#access-log-policy) for the
as-built keys:

```json
{"level":"info","timestamp":"2026-07-09T02:12:04.455Z","caller":"httpmw/logging.go:192","message":"HTTP request","trace_id":"94c290a2e22a985f6f9fa2337e476443","http.request.method":"GET","http.route":"/order/v1/private/orders","http.response.status_code":200,"duration_seconds":0.042}
```

What `kubectl logs` shows **today** carries the legacy keys the same middleware
still emits — `method`, `path`, `status`, `duration`, plus `client_ip` and
`user_agent` — so a query written against the target keys above returns nothing on
the current fleet. The envelope (`level`, `timestamp`, `caller`, `message`,
`trace_id`) is identical in both shapes.

The stdout line is also exported over OTLP by
the otelzap tee, and the collector's `logs` pipeline writes it to **both** VictoriaLogs and
ClickHouse. The two are retention tiers, not a mistake: 7 days of LogsQL for ops, 90 days of
SQL for questions that cross days.

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

`trace_id`/`span_id` are injected from the OpenTelemetry span context in `httpmw.Logging`, so a log line and its trace join on one id.

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
| `Resource` | `pkg/obsx` resource (`service.name`, namespace, pod — from `OTEL_SERVICE_NAME` + Downward API; `service.version` only on the versioned order worker today — the controller-derived build id, read from the `temporal.io/build-id` pod label, ADR-054) |
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

Infra ingest headers (`VL-Msg-Field`, Vector streams) are documented in [VictoriaLogs (platform)](../observability/logging/victorialogs.md#per-sender-ingest-contract).

---

## Event and field naming

- **Message** is stable and concise — not a dump of dynamic IDs.
- A pinned semantic-convention key is used whenever one exists; a platform key is
  lowercase and dot-separated (`order.id`, `checkout.session.id`), matching the
  convention's own shape.
- Only a name from the [§ Event catalog](#event-catalog) may be an **`event`** value,
  and only `slogx.Event` sets it.
- Do not put IDs into message templates when fields can carry them.
- Do not create one-off aliases such as `orderId`, `order_id`, and `oid` for the same concept.
- Errors use one shape: `error.type` plus a redacted `error.message`.

Today's services still write snake_case keys through zap; the shape below is what
they move to in RFC-0031 Phase 3.

```go
log.Event(ctx, slog.LevelInfo, "order.confirmed", "order confirmed",
    slog.String("order.id", orderID))

log.Error(ctx, "compensation failed", slogx.Err(err),
    slog.String("order.id", orderID))
```

## Event catalog

> **Frozen by RFC-0031 Task 0.2 — not yet emitted.** This is the registered list
> a service may emit through `slogx.Event`. It takes effect when the fleet moves to
> `logger/slogx` (RFC-0031 Phase 3); until then no record carries these names. Owner
> sign-off is the merge of the change that introduced this section.

The catalog is deliberately small. A name is admitted only when an operator would
query it **by name across services**; a detail read while following one request
belongs in the access record or a diagnostic log instead, and a count already kept by
a business metric does not need a second copy as an event. Adding a name is a
reviewed change to this table, never a decision made at a call site.

Names follow the grammar the facade enforces: lowercase segments of
`[a-z][a-z0-9_]*`, joined by dots, at least two, at most 64 bytes. A name is an
operation class, so it never contains an id. Where a row lists `outcome`, the event
carries it as a bounded value from the listed set; that is the same key ADR-075 puts
on a span for a business rejection.

| Class | Event | Emitted at | Attributes | Owner |
|---|---|---|---|---|
| Business state transition | `order.created` | order row committed as `pending` | `order.id` | [order](./order.md) |
| | `order.confirmed` | saga moves the order to `confirmed` | `order.id` | order |
| | `order.failed` | saga ends the order `failed` | `order.id`, `reason` (ReasonCode), `outcome`: `failed` \| `compensated` | order |
| | `order.cancelled` | cancellation workflow reaches `cancelled` | `order.id`, `order.epoch` | order |
| | `order.manual_review.entered` | order parked for a human decision | `order.id`, `reason` | order |
| | `payment.authorization.completed` | authorize decision stored | `payment.id`, `order.id`, `outcome`: `authorized` \| `declined` \| `unknown` | [payment](./payments.md) |
| | `payment.capture.completed` | capture decision stored | `payment.id`, `outcome`: `succeeded` \| `declined` \| `unknown` | payment |
| | `payment.refund.completed` | refund settled | `payment.id`, `refund.id`, `outcome`: `succeeded` \| `declined` \| `unknown` | payment |
| | `payment.reconciliation.discrepancy.detected` | reconciliation run finds a mismatch | `reconciliation.run_id`, `discrepancy.class` | payment |
| | `checkout.session.confirmed` | session handed to order | `checkout.session.id`, `order.id` | [checkout](./checkout.md) |
| | `checkout.session.requoted` | confirm sent the buyer back to requote | `checkout.session.id`, `reason`: `price_changed` \| `stock_unavailable` \| `availability_unknown` | checkout |
| | `checkout.session.expired` | session expired | `checkout.session.id`, `reason`: `timer` \| `lazy` | checkout |
| | `inventory.reservation.rejected` | reserve refused | `inventory.reservation.ref`, `outcome`: `insufficient` \| `unknown_sku` | [inventory](./inventory.md) |
| Retry exhausted | `order.retry.exhausted` | a bounded retry gives up and the order is escalated | `order.id`, `operation`: `completion` \| `inventory_commit` \| `fulfillment_start` \| `cancellation_start` \| `compensation`, `error.type`, `attempts` | order |
| Compensation | `order.compensation.completed` | one compensation step finishes | `order.id`, `compensation.step`: `void_payment` \| `refund_payment` \| `release_stock` \| `cancel_shipment` \| `fail_order` \| `mark_manual_review`, `outcome`: `ok` \| `failed`, `error.type` when failed | order |
| Workflow lifecycle | `temporal.workflow.started` | the client starts a workflow | `temporal.workflow.type`, `temporal.task_queue` | [pkg](./pkg.md) (`temporalx`) |
| | `temporal.workflow.failed` | a run ends failed, terminated or timed out | `temporal.workflow.type`, `temporal.run_status` | pkg |
| Startup/shutdown | `process.started` | entry point ready to serve | `component`: `api` \| `worker` \| `mockpay` | pkg (`slogx`) |
| | `process.stopped` | entry point finished shutting down | `component`, `outcome`: `graceful` \| `error` | pkg |

**Workflow lifecycle events are never written from workflow code.** Workflow code is
replayed, and only the SDK's replay-aware logger may run there; these two names are
emitted by the client that starts the run or by the activity or dispatcher that
observes its end.

**Deliberately not in the catalog.** Cart, review, notification, shipping, user and
product transitions are single-service facts already counted by their business
metrics (`cart.cleared.total`, `reviews.duplicate_rejected.total`,
`shipment.created.total`, …). Payment void is covered from the order side by
`order.compensation.completed`. Reconciler repair and breach findings stay
diagnostic until an operator needs them across runs.

### Access-record severity

The access record is a fixed schema owned by the shared middleware and carries no
event name. Its severity is set by outcome, not by the caller:

| Transport | Error | Warn | Info |
|---|---|---|---|
| HTTP | status ≥ 500 | status 400–499 | everything else |
| gRPC | `UNKNOWN`, `UNIMPLEMENTED`, `INTERNAL`, `DATA_LOSS`, any unknown code | `DEADLINE_EXCEEDED`, `PERMISSION_DENIED`, `RESOURCE_EXHAUSTED`, `FAILED_PRECONDITION`, `ABORTED`, `OUT_OF_RANGE`, `UNAVAILABLE` | `OK`, `NOT_FOUND`, `CANCELLED`, `ALREADY_EXISTS`, `INVALID_ARGUMENT`, `UNAUTHENTICATED` |

Severity answers *who should look*; `error.type` answers *did the server fail*, and
follows the span: HTTP sets it to the status code for a 5xx, gRPC sets it to the code
for the six codes the pinned instrumentation marks the server span Error for. The two
axes differ on purpose — a `DEADLINE_EXCEEDED` is a Warn and still an error.

### Field classification

Every attribute a record may carry falls in one class. The facade enforces `deny`
before any sink; `review` fields need a named owner, purpose and retention rule, agreed
in the change that first emits them.

| Class | Fields | Where allowed |
|---|---|---|
| Allow | service identity (`service.*`, `deployment.environment.name`); `http.request.method`, `http.route`, `http.response.status_code`; `rpc.system.name`, `rpc.method`, `rpc.response.status_code`; `error.type`; `event`; the bounded enums in the catalog (`outcome`, `reason`, `operation`, `compensation.step`, `discrepancy.class`, `component`); `temporal.workflow.type`, `temporal.task_queue`, `temporal.run_status` | logs, traces, metrics labels where bounded |
| Allow — correlation only | `order.id`, `payment.id`, `refund.id`, `checkout.session.id`, `inventory.reservation.ref`, `reconciliation.run_id`, `order.epoch`, `attempts`, Temporal workflow and run ids | logs and traces only; never metric labels, resource attributes, event names or profile labels |
| Review | `user.id`, email, phone, postal address, person names, monetary amounts, provider response text, any free-text a user typed | nowhere until reviewed |
| Deny | authorization, cookies, passwords, tokens, secrets, API and private keys, card numbers and CVV, connection strings and DSNs, idempotency keys, client address, peer address, User-Agent, headers, request and response bodies, payloads, a raw error string | never — the facade replaces them |

### Schema owners

| Schema | Owner | Contract |
|---|---|---|
| HTTP access record | `pkg/httpmw` | [§ Access-log policy](#access-log-policy) |
| gRPC access record | `pkg/grpcx` | [§ Access-log policy](#access-log-policy) |
| Temporal SDK and workflow logging | `pkg/temporalx` (on the SDK's replay-aware logger) | [temporal.md](./temporal.md) |
| Named events | the owning service, per row above | this section |
| ClickHouse query schema | platform observability | [ClickHouse schema and queries](../observability/clickhouse/schema-and-queries.md) |

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
> [api.md § Deadlines, retries, and health](./api.md#deadlines-retries-and-health)
> for probe filtering). The rename to this schema —
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
(`grpc.health.v1.Health` + reflection skipped); on HTTP, `httpmw.Logging` reads
the same `httpmw.DefaultSkipRoutes` map as `httpmw.Tracing`, so the two skip
lists cannot drift apart. Only a **successful** probe is skipped — a failing one
is always logged. HTTP matching is **exact** against the Gin route pattern
(`c.FullPath()`), so a probe aimed at a path the service never registered
matches no route and is logged like any other 404. Signal matrix:
[Application observability § Health filtering](./observability.md#health-readiness-and-reflection-filtering).

---

## Error logging ownership

Lower layers return typed errors. The boundary that decides return, retry,
compensate, abandon, or escalate owns the **error** log. Access middleware owns
the final request/RPC summary.

Full rules: [Application observability § Error ownership](./observability.md#error-ownership).

**Planned shape (RFC-0031, available in `logger/slogx` v0.1.0, not yet deployed).**
`slogx.Err(err)` is the one error shape: `error.type` carries the concrete Go type of
the deepest cause that is not a standard-library wrapper, and `error.message` the
redacted, bounded text. The label is only as useful as the errors behind it — every
`errors.New` sentinel reports `errors.errorString`, so a domain whose failures should
be distinguishable on a dashboard declares error types.

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

_Last updated: 2026-09-23 — RFC-0031 Task 0.2 freeze: § Event catalog (nineteen names across five classes), the access-record severity mapping, a per-field classification and one owner per schema; § Event and field naming moves to dotted keys. Previously 2026-09-23 — `logger/slogx` v0.1.0 is tagged: the Target-contract callout says the facade exists but no service has adopted it, names the one breaking query change (`error` as a string becomes `error.type` + `error.message`) and the two added levels, and § Error logging ownership carries the planned `Err` shape. Previously 2026-09-18 — RFC-0031 accepted: Design record links ADR-070/ADR-071 and a labelled **Target contract** callout names `slogx`, the semconv access record and the event catalog as planned; the as-built `zapx` contract below is unchanged. Previously 2026-09-17 — the opening access-log sample is labelled as the contract target and the as-built keys (`method`/`path`/`status`/`duration`/`client_ip`/`user_agent`) are stated beside it, so the first example no longer contradicts § Access-log policy; the trace sink count is corrected to **two**. Previously 2026-08-23 — logs go to **two** stores (VictoriaLogs + ClickHouse). Previously 2026-08-22 — RFC-0026/ADR-054: the Temporal Worker Controller owns the versioned-worker lifecycle._
