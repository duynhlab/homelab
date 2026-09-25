# Application Logging

Structured logging contract for every Go service and worker in the platform service catalog — the `logger/slogx` facade, JSON shape, levels, and OTLP export of the same redacted record.

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **Logger** | `github.com/duynhlab/pkg/logger/slogx` v0.2.0 (fleet-wide since 2026-09-24, RFC-0031 Phase 3) | [ADR-070](../proposals/adr/ADR-070-logging-facade-and-event-catalog/) |
| **Format** | One redacted record → JSON envelope on stdout + OTLP logs when `OTEL_LOGS_ENABLED=true` | [ADR-071](../proposals/adr/ADR-071-telemetry-event-data-contract/) |
| **Correlation** | `trace_id` / `span_id` from the span in the `ctx` passed to each call | — |
| **Platform pipeline** | [Logging (platform)](../observability/logging/README.md) — dual-path ingest (OTLP + Vector) into **two** stores: VictoriaLogs (7d, LogsQL) and ClickHouse `otel_logs` (90d, SQL) | — |
| **Cross-cutting** | [Application observability](./observability.md) — middleware order, env, `obsx` | — |
| **Design record** | — | [RFC-0014](../proposals/rfc/RFC-0014/) · **[RFC-0031](../proposals/rfc/RFC-0031/) (Accepted 2026-09-17; as-built 2026-09-24)** → [ADR-070](../proposals/adr/ADR-070-logging-facade-and-event-catalog/) (slog facade, event catalog) · [ADR-071](../proposals/adr/ADR-071-telemetry-event-data-contract/) (access/event schema, privacy) |

---

## Overview

Every service and worker logs through the shared **`logger/slogx`** facade — a
context-first API over the standard library's `slog`. Each call builds **one**
record, redacts it **once**, and renders it to two sinks: the JSON envelope on
stdout and an OTLP log record (see [OpenTelemetry integration](#opentelemetry-integration)).

**Current status (RFC-0031 Phase 3, 2026-09-24):** all ten services, `order-worker`,
`checkout-worker` and `mockpay` pin `logger/slogx` v0.2.0, and no release image links
`go.uber.org/zap`, otelzap, `zerolog` or `clog`. `zapx`, `zerolog` and `clog` are
retired from `duynhlab/pkg` (their tags still resolve). The OTLP branch goes through the
global logger provider `obsx` installs to the OpenTelemetry Collector, which exports to
**two** stores: **VictoriaLogs** (7-day ops retention, LogsQL) and **ClickHouse**
`otel_logs` (90-day SQL, [ADR-023](../proposals/adr/ADR-023-clickhouse-observability-olap/)).
Stdout is still emitted for `kubectl logs`.

Scope and shared bootstrap rules: [Application observability](./observability.md).

> **What changed for stored queries at the cutover.** The six envelope keys —
> `timestamp`, `level`, `message`, `caller`, `trace_id`, `span_id` — are reserved. The
> first five are what `zapx` emitted, so queries on them survived untouched; `span_id`
> on stdout is new (the zap era wrote only `trace_id` there).
> The error field changed: `zap.Error(err)` wrote one string field `error`;
> `slogx.Err(err)` writes two flat fields, `error.type` (the Go type, the
> low-cardinality label the span also carries) and `exception.message` (the text, redacted
> and bounded; `error.message` until slogx v0.3.0, when the deprecated upstream key was
> retired). A panel, alert or saved LogsQL filter matching `error` as a string must
> use `exception.message`, or better `error.type`. The access record moved from
> `method`/`path`/`status`/`duration`/`client_ip`/`user_agent` to the semconv keys in
> [§ Access-log policy](#access-log-policy). Two levels joined the four: `trace`
> (severity 1) and `fatal` (21); on OTLP the severity *number* is the field to filter,
> because the bridge writes severity text with the standard library's spelling, which
> has no name for those two.

---

## Pod log verification

```bash
# Uniform slogx JSON envelope, with trace_id/span_id when a span is active
kubectl logs -n order deployment/order --tail=50
kubectl logs -n cart deployment/cart --tail=50
```

### Log output format

Canonical access-log line (middleware-owned summary, as emitted by `httpmw.Logging`):

```json
{"timestamp":"2026-09-24T02:12:04.455Z","level":"info","caller":"httpmw@v0.2.0/logging.go:144","message":"HTTP request","http.request.method":"GET","http.route":"/order/v1/private/orders","http.response.status_code":200,"trace_id":"94c290a2e22a985f6f9fa2337e476443","span_id":"5b8efff798038103"}
```

The record carries no raw path, query, client address, User-Agent or duration — the
span and the RED histogram measure latency. See [Access-log policy](#access-log-policy)
for the full key set.

The same redacted record is exported over OTLP by the facade's second sink, and the
collector's `logs` pipeline writes it to **both** VictoriaLogs and ClickHouse. The two
are retention tiers, not a mistake: 7 days of LogsQL for ops, 90 days of SQL for
questions that cross days.

---

## The `slogx` logger

All services build the logger from the shared facade (`github.com/duynhlab/pkg/logger/slogx`):

- **JSON envelope** on stdout: `timestamp` (ISO8601, UTC, millisecond), `level`
  (lowercase: `trace|debug|info|warn|error|fatal`), `caller` (`<dir>/<file>.go:<line>`),
  `message`, then the record's attributes, then `trace_id` / `span_id` when the `ctx`
  carries a valid span.
- Level parsed from `LOG_LEVEL` (`debug|info|warn|error`; `trace` is accepted for local
  investigation); anything else means `info`.
- Every emission takes a `context.Context` (`Info(ctx, msg, attrs…)`); correlation
  comes from that `ctx`, never from bound fields.
- `slogx.FromContext` / `slogx.WithContext` carry a logger through code that receives
  only a context; `slogx.SetDefault` installs the configured logger as the fallback.
- `Logger.Slog()` hands the same handler chain (redaction, level gate, both sinks) to
  shared middleware and SDK bridges that need a `*slog.Logger`.
- `Logger.Fatal` is for bootstrap failures only: it writes the record, calls the
  configured `Flush`, and exits with status 1.

**Service wiring** (as built in the service `cmd/main.go` files; inventory mounts
`Logging` and `Recovery` but not `Tracing`, and only services that serve gRPC call
`grpcx.NewServer` — not user or checkout):

```go
logger := slogx.New(slogx.Config{Level: cfg.Logging.Level})
slogx.SetDefault(logger)

obs, err := obsx.SetupObservability(ctx, obsx.ConfigFromEnv())
if err != nil {
    logger.Warn(ctx, "Failed to initialize OpenTelemetry", slogx.Err(err))
} else {
    // The OTLP sink reads the global logger provider obsx installed; the
    // rebuild only wires Flush, so a Fatal record is exported before exit.
    logger = slogx.New(slogx.Config{Level: cfg.Logging.Level, Flush: obs.ForceFlush})
    slogx.SetDefault(logger)
}

r := gin.New() // not gin.Default: its logger and recovery bypass the facade
r.Use(httpmw.Tracing(serviceName))
r.Use(httpmw.Logging(logger.Slog()))
r.Use(httpmw.Recovery(logger.Slog()))

grpcSrv, _ := grpcx.NewServer(logger.Slog())
// order and checkout: temporalx.Dial(..., temporalx.WithLogger(logger.Slog()))
```

Business code logs through `slogx.FromContext(ctx)` or an injected `*slogx.Logger`,
always passing the request `ctx`.

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

| Range | Meaning | `slogx` level mapped by the OTel slog bridge |
|-------|---------|----------------------------------------------|
| 1–4 | TRACE | `slogx.LevelTrace` → 1 |
| 5–8 | DEBUG | `slog.LevelDebug` → 5 |
| 9–12 | INFO | `slog.LevelInfo` → 9 |
| 13–16 | WARN | `slog.LevelWarn` → 13 |
| 17–20 | ERROR | `slog.LevelError` → 17 |
| 21–24 | FATAL | `slogx.LevelFatal` → 21 (`Logger.Fatal` only) |

### How the platform stack fills the LogRecord

| LogRecord field | Filled by |
|-----------------|-----------|
| `Timestamp` | record time (stdout `timestamp`) |
| `ObservedTimestamp` | OTel log SDK when the record is emitted |
| `TraceId`, `SpanId`, `TraceFlags` | the span in the `ctx` passed to the call, read by the bridge (stdout gets `trace_id` / `span_id` from the same span) |
| `SeverityText`, `SeverityNumber` | slog level via the OTel slog bridge — filter on the number; the text reads `DEBUG-4` / `ERROR+4` for trace and fatal |
| `Body` | record `message` |
| `Resource` | `pkg/obsx` resource (`service.name`, namespace, pod — from `OTEL_SERVICE_NAME` + Downward API; `service.version` from `OTEL_RESOURCE_ATTRIBUTES` — the image tag on every API service and mockpay, the controller-derived build id on the two versioned workers, read from the `temporal.io/build-id` pod label, ADR-054) |
| `InstrumentationScope` | always `github.com/duynhlab/pkg/logger/slogx` — the facade's package path, never the service name |
| `Attributes` | every redacted `slog.Attr` on the record; the source location rides as `code.*` attributes (stdout shortens it to `caller`) |

Every field in this mapping is wired by shared code (`pkg/obsx`, `slogx`,
middleware) — a service author only writes `logger.Info(ctx, message, attrs…)` and
the full LogRecord shape falls out.

---

## Log level standards

Platform severity taxonomy — use when choosing which `slogx` method to call or
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

### Library level mapping (`slogx`)

The fleet runs **`slogx`** (RFC-0031 Phase 3, 2026-09-24) — see
[Migration history](#migration-history). The earlier `zapx`, `zerolog` and `clog`
adapters were removed from `duynhlab/pkg` the same day.

| User Standard | `slogx` (`slog.Level`) |
|----------------|------------------------|
| panic (5) | N/A (the facade has no panic method) |
| fatal (4) | `slogx.LevelFatal` (12), written only by `Logger.Fatal` |
| error (3) | `slog.LevelError` (8) |
| warn (2) | `slog.LevelWarn` (4) |
| info (1) | `slog.LevelInfo` (0) |
| debug (0) | `slog.LevelDebug` (-4) |
| trace (-1) | `slogx.LevelTrace` (-8) |

`fatal` is a **logger method** (`logger.Fatal`) for process bootstrap failures —
not a valid `LOG_LEVEL` value. `trace` is accepted by the facade for local
investigation; service config validation admits only the four runtime values below.

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

- Logger: `slogx.New(slogx.Config{Level: …})` with the service's `LOG_LEVEL` (the validated config value, or the env var directly in services that read it there). The facade recognises the runtime values; anything else defaults to `info`.
- One level gate: it sits above both sinks, so debug records suppressed on stdout are not exported over OTLP either.

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
| `error.type`, `exception.message` | the operation has an error (`slogx.Err(err)`) |
| domain/workflow identifiers | operationally justified and permitted by the [common data policy](./observability.md#cross-signal-data-and-privacy-policy) |

### OTLP export (app path)

- The OTel slog bridge maps the record `message` to the OTLP log body and attaches the redacted attributes as attributes.
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
- Errors use one shape: `error.type` plus a redacted `exception.message`.

The facade call shape:

```go
log.Event(ctx, slog.LevelInfo, "order.confirmed", "order confirmed",
    slog.String("order.id", orderID))

log.Error(ctx, "compensation failed", slogx.Err(err),
    slog.String("order.id", orderID))
```

## Event catalog

> **Frozen by RFC-0031 Task 0.2; emitted since 2026-09-24.** This is the registered
> list a service may emit through `slogx.Event`. Owner sign-off is the merge of the
> change that introduced this section. Observed live on Kind in ClickHouse
> `otel_logs` (`LogAttributes['event']`) during the 2026-09-24 audit:
> `process.started` (all 13 identities — 10 services, `order-worker`,
> `checkout-worker`, `mockpay`; untraced by design), `order.created`,
> `temporal.workflow.started`, `order.confirmed`, `order.manual_review.entered`,
> `order.compensation.completed`, `payment.authorization.completed`,
> `payment.capture.completed`, `payment.refund.completed` and
> `checkout.session.confirmed` — every request-scoped one carrying a trace id. The
> compose release gate observed 15 names. Catalog names outside the Kind list above
> were not observed in that audit.

An event is emitted only after the decision it names is stored, and only by the caller
that stored it.

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

The registry in `duynhlab/pkg` (`semconv/`, ADR-076) declares the same 19 names;
`make semconv-catalog-check` (CI) fails when this table and the registry's generated
catalog disagree on a name, class, attribute set or owner.

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
observes its end. `temporalx.WithLogger` installs the client interceptor that writes
`temporal.workflow.started`.

Domain events that are *decided* in workflow code — `order.failed`,
`order.compensation.completed`, the saga's `order.retry.exhausted` — go through
`temporalx.WorkflowEvent`, which writes via that replay-aware logger, so a replayed
history writes nothing. An activity's `error.type` comes from the Temporal
`ApplicationError.Type()`. Everywhere else a service uses the facade's `Event`.

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
| Allow — correlation only | `order.id`, `payment.id`, `refund.id`, `checkout.session.id`, `inventory.reservation.ref`, `reconciliation.run_id`, `order.epoch`, `attempts`, Temporal workflow and run ids; `product.id`, `review.id`, `shipment.id`, `notification.id`, `payment.provider_id`, `webhook.event_id` (catalog, provider and delivery ids the Phase 3 cutover writes on diagnostic records — none identifies a person) | logs and traces only; never metric labels, resource attributes, event names or profile labels |
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

**Access-log field schema (as built — `pkg/httpmw` v0.2.0, `pkg/grpcx` v0.37.0):**

| Field | Notes |
|-------|-------|
| `message` | `HTTP request` / `gRPC request` |
| `http.request.method` | HTTP verb — the nine standard methods, anything else `_OTHER` |
| `http.route` | Matched route template, never the raw path; omitted when no route matched |
| `http.response.status_code` | Final status |
| `rpc.system.name`, `rpc.method` | gRPC access logs (`rpc.method` is `package.Service/Method`) |
| `rpc.response.status_code` | gRPC status by its spec name (`NOT_FOUND`, `CANCELLED`) — the value the span carries |
| `error.type` | HTTP: the status code as a string for a 5xx, `panic` when `httpmw.Recovery` caught one; gRPC: the code for the six codes the server span marks Error |
| `trace_id`, `span_id` | When span context exists (from the request `ctx`) |

The record carries **no** raw path or query, client address, User-Agent, peer
address or duration — they leak identifiers or personal data per the
[data policy](./observability.md#cross-signal-data-and-privacy-policy), and the span
and the RED histogram already measure duration. See [tracing.md](./tracing.md) for
the span attributes and
[api.md § Deadlines, retries, and health](./api.md#deadlines-retries-and-health)
for probe filtering.

Level policy: HTTP logs `error` for status ≥ 500, `warn` for 400–499, else
`info` — a rejected request is not a broken service. gRPC follows
the **status-code class** (pkg ≥ v0.31.0, verbatim from go-grpc-middleware's
`DefaultServerCodeToLevel`): caller-attributable outcomes at `info`
(`OK`, `NotFound`, `Canceled`, `AlreadyExists`, `InvalidArgument`,
`Unauthenticated`), degraded-but-explicable at `warn` (`DeadlineExceeded`,
`PermissionDenied`, `ResourceExhausted`, `FailedPrecondition`, `Aborted`,
`OutOfRange`, `Unavailable`), faults at `error` (`Unknown`, `Unimplemented`,
`Internal`, `DataLoss`; unknown codes default to `error`). This is as-built:
every service except user pins `pkg/grpcx v0.37.0`; eight of them serve gRPC
(not user, not checkout, which uses grpcx only as a client). HTTP
messages are `HTTP request`, gRPC messages are `gRPC request`.

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

**Error shape (as built, `logger/slogx` v0.3.0).**
`slogx.Err(err)` is the one error shape: `error.type` carries the concrete Go type of
the deepest cause that is not a standard-library wrapper, and `exception.message` the
redacted, bounded text (the upstream conventions deprecated `error.message`, so the
registry live-check would have flagged every error record). The label is only as useful as the errors behind it — every
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

- **One record, two sinks:** the facade's handler chain is redaction → one level gate → {JSON stdout, OTel slog bridge}. The bridge reads the global logger provider `pkg/obsx` installs, whose batching processor ships records over OTLP (`otlploghttp`) to the OpenTelemetry Collector. No service constructs a provider or exporter.
- **`OTEL_LOGS_ENABLED`** gates the exporter (enabled fleet-wide since RFC-0014 P4). With it off the global provider is a no-op and the OTLP sink is skipped. See [Application observability](./observability.md#environment-variables).
- **Flush:** services pass `obs.ForceFlush` as `slogx.Config.Flush`, so a `Fatal` record is exported before exit, and write `process.stopped` before the OTel SDK shutdown — see [Graceful shutdown](./graceful-shutdown.md).
- App pods carry `platform.duynhlab.dev/otlp-logs=true` and are **excluded** from Vector — the double-ingest guard. Full pipeline: [Logging (platform)](../observability/logging/README.md).

---

## Examples

```go
logger.Info(ctx, "Database connection pool established")

logger.Warn(ctx, "dependency call degraded",
    slog.String("operation", "product.get_details"),
    slogx.Err(err),
)

slogx.FromContext(ctx).Event(ctx, slog.LevelInfo, "order.created", "order created",
    slog.String("order.id", orderID))

logger.ProcessStarted(ctx, slogx.ComponentAPI) // process.started
```

Do not log collector or Pyroscope endpoints when they could contain embedded credentials.

---

## Migration history

RFC-0031 Phase 3 (2026-09-24) moved every service and worker from `zapx` to
`logger/slogx` in one release train and removed `zapx`, `zerolog` and `clog` from
`duynhlab/pkg`; stdout envelope keys were kept, the error and access-record fields
changed (see [Overview](#overview)).

Pre-P4 library migrations (RFC-0014 P4 converged the fleet on `zapx`, historical):

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

Before RFC-0014 P4, three loggers coexisted (zap, clog, zerolog). The otelzap tee needed one uniform zap core. Converging removes field-shape divergence (`msg` vs `message`, Unix vs ISO8601 time).

---

## References

- [Application observability](./observability.md)
- [Logging (platform)](../observability/logging/README.md)
- [RFC-0014: observability standardization](../proposals/rfc/RFC-0014/)
- [RFC-0031: logging and telemetry overhaul](../proposals/rfc/RFC-0031/)

_Last updated: 2026-09-24 — RFC-0031 as-built (Task 4.3): the fleet logs through `logger/slogx` v0.2.0 — one redacted record to the stdout envelope and OTLP via the global provider `obsx` installs, `obs.ForceFlush` wired as `Flush`; the access-record schema is the as-built semconv set (no path, client address, User-Agent or duration); the event catalog is emitted, with the names observed live; level mapping, LogRecord mapping, wiring and examples rewritten from `zapx`/otelzap to `slogx`. Previously 2026-09-23 — RFC-0031 Task 0.2 freeze: § Event catalog (nineteen names across five classes), the access-record severity mapping, a per-field classification and one owner per schema; § Event and field naming moves to dotted keys. Previously 2026-09-23 — `logger/slogx` v0.1.0 is tagged: the Target-contract callout says the facade exists but no service has adopted it, names the one breaking query change (`error` as a string becomes `error.type` + `error.message`) and the two added levels, and § Error logging ownership carries the planned `Err` shape. Previously 2026-09-18 — RFC-0031 accepted: Design record links ADR-070/ADR-071 and a labelled **Target contract** callout names `slogx`, the semconv access record and the event catalog as planned; the as-built `zapx` contract below is unchanged. Previously 2026-09-17 — the opening access-log sample is labelled as the contract target and the as-built keys (`method`/`path`/`status`/`duration`/`client_ip`/`user_agent`) are stated beside it, so the first example no longer contradicts § Access-log policy; the trace sink count is corrected to **two**. Previously 2026-08-23 — logs go to **two** stores (VictoriaLogs + ClickHouse). Previously 2026-08-22 — RFC-0026/ADR-054: the Temporal Worker Controller owns the versioned-worker lifecycle._
