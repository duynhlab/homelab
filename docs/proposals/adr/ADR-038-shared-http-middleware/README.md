# ADR-038: Promote the HTTP tracing and logging middleware into `pkg/httpmw`

> **Decision summary:** We will move the copied `TracingMiddleware` /
> `LoggingMiddleware` pair out of the eleven service repositories into a new
> Layer 1 module `github.com/duynhlab/pkg/httpmw`, because that duplication has
> now produced two fleet-wide observability defects that had to be found by
> audit rather than by review. We accept a cross-repo adoption phase — one pkg
> release, eleven PRs, eleven pins — in exchange for one place where the edge
> contract of every Go service is written down and tested.

| Attribute | Value |
|-----------|-------|
| **Status** | Proposed |
| **Decision date** | — |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | The gin HTTP middleware chain of every Go API service: request tracing, the access log, and trace-context correlation. Not gRPC (`pkg/grpcx` already owns it), not workers |
| **Affected components** | `duynhlab/pkg` (new module), all 11 `*-service` repos, `docs/api/observability.md` |
| **Related RFC** | [RFC-0014](../../rfc/RFC-0014/) |
| **Related research** | [Telemetry audit 2026-08-07](../../../observability/audit-2026-08-07.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | Not started — this ADR decides the direction only |
| **Adoption** | Not started |

## Context

[`docs/api/observability.md`](../../../api/observability.md) is the normative
instrumentation contract, and it already admits the problem in its own words
(`:147`):

> providers (`pkg/obsx`), gRPC (`pkg/grpcx`), and DB (`pkg/dbx` + otelpgx) are
> shared libraries; the HTTP `TracingMiddleware`/`LoggingMiddleware` pair and the
> span helpers are **copied per service** under `<svc>-service/middleware/`, and
> the copies are drifting apart release by release. Promoting them into `pkg` is
> a target, not current reality.

The 2026-08-07 telemetry audit turned that acknowledged risk into measured
defects. Two of its findings are the same duplication seen from two angles:

- **F-2** — the access log emits a record for every readiness and liveness
  probe. On `auth`, **3 395 of 3 401** access-log records were successful
  probes, and every service sat in the same band. Metrics and traces exclude
  probes correctly, because `TracingMiddleware` carries the skip list
  (`auth-service/middleware/tracing.go:40`) — and `logging.go` carries no
  health reference at all. The contract claims both use the same list
  (`observability.md:178`); as built, only one does.
- **F-1** — the access log fabricates a trace id when no span exists
  (`generateTraceID()`, `auth-service/middleware/logging.go:44,67-75`), so probe
  logs advertise a correlation that cannot exist; and two services never pass
  the trace context at all while nine do.

Neither defect is subtle, and neither survived contact with a query. What
allowed them to persist is that there is no single artifact to review: eleven
copies, each individually plausible. `pkg/AGENTS.md` names the same hazard from
the library side — *"A change to `obsx.ZapCore`'s contract … affects every
service's `middleware/logging.go`"* — which is a statement that a shared
contract already exists, just not in a shared place.

Meanwhile the sibling precedent is established and healthy: **`pkg/authmw`** is
a gin middleware module consumed by six services, and `pkg/grpcx` already owns
the equivalent surface for gRPC — server span, RPC RED metrics, access log, and
health/reflection filtering, all in one place.

## Scope

**In scope:** the gin `TracingMiddleware` and `LoggingMiddleware` pair, the
health/readiness skip list they share, the access-log field schema, the trace-id
resolution rule, and the logger-into-context carrier.

**Out of scope:** `pkg/grpcx` (already shared), worker and Temporal
instrumentation, the `obsx` bootstrap itself, and the per-service business
metrics. Service-specific span helpers stay in their repos unless a second
service needs them.

## Decision drivers

1. **A defect found by audit should be reviewable in one diff.** F-1 and F-2
   each required eleven near-identical fixes; the next one will too.
2. **The contract already claims sharing.** `observability.md:178` describes one
   skip list. Making that true is cheaper than weakening the contract.
3. **The layering must not be broken to achieve it** — see below; this is the
   constraint that shapes the design.
4. **Adoption must be optional per service and reversible**, because eleven
   simultaneous forced migrations is exactly the risk profile this platform has
   learned to avoid.

## Decision

Create **`github.com/duynhlab/pkg/httpmw`** as a **Layer 1** module exporting the
tracing and logging middleware, the shared skip list, and the access-log schema.
Services replace their `middleware/` copies with it, one PR at a time.

### The layering constraint, and why `httpmw` must not import `obsx`

`pkg/AGENTS.md` sets strict layers enforced by `depguard`, and states plainly:
**"No module in this repository may import a Layer 2 module."** `obsx` is Layer
2. A naive `httpmw` that called `obsx.TraceContext(ctx)` to bind trace context
onto the log record would therefore be **unimplementable** — the linter would
reject it, and correctly so, because it would drag the OpenTelemetry SDK into
every consumer of a middleware package.

It does not need to. `obsx.TraceContext` (`obsx/logctx.go:40`) is nine lines and
builds one value:

```go
zap.Field{Key: "otel.trace_context", Type: zapcore.SkipType, Interface: ctx}
```

Nothing in that requires the SDK. `httpmw` constructs the same field itself
using only the OpenTelemetry **API** (`go.opentelemetry.io/otel/trace`), which
Layer 1 is explicitly permitted to import. The otelzap bridge on the far side
reads it by interface assertion and neither module needs to know about the
other.

The same reasoning covers trace-id resolution: `obsx.TraceIDFromContext`
(`obsx/metrics.go:21`) is `trace.SpanFromContext(ctx).SpanContext()` — API only.
`pkg/grpcx` already re-derives it privately for exactly this reason, which
`pkg/docs/MIGRATION.md` records as a deliberate v0.36.0 change.

**Consequence for the ADR:** `httpmw` depends on `logger/zapx` (Layer 0) and the
OTel API, and on nothing else inside pkg. `obsx` stays the only SDK owner.

### Naming

**`httpmw`**, mirroring `authmw`. `pkg/AGENTS.md` says new modules take an `x`
suffix, and this deliberately deviates: the `x` convention exists to mark
"our wrapper around a third-party package" (`httpx`, `grpcx`, `dbx`), while the
`mw` suffix already marks "gin middleware" and has a sibling. Consistency with
the nearest neighbour beats consistency with the broader rule here, and the
deviation is recorded rather than silent.

### What the module owns

| Surface | Rule it makes true |
|---|---|
| One skip list, exported | `observability.md:178` — probes excluded from spans, RED metrics **and** the access log, from a single list |
| Trace id resolution | Return the span's id, or **empty** — never a fabricated one. Removes F-1's root cause by construction |
| Trace-context binding | The `SkipType` field, built from the OTel API, so OTLP log records carry native `trace_id`/`span_id` |
| Access-log schema | The semconv field set from [`logs.md`](../../../api/logs.md), one record per request |
| Level by class | `warn` for 4xx, `error` for 5xx — expected business rejections are not infrastructure errors |
| Middleware order | tracing → logging, expressed as one constructor so the order cannot be got wrong |

## Alternatives considered

**Patch the eleven copies and stop there.** This is what the F-1/F-2 fix wave
does, and it is the right immediate move — it stops the log bleeding now without
a cross-repo dependency change. Rejected as the *end state* because it leaves
the next shared defect exactly as expensive as this one, and the drift the
contract complains about untouched.

**Nested module under `obsx` (`obsx/httpmw`).** `pkg/AGENTS.md` calls nested
modules "the escape hatch" for genuine Layer 2 needs. Rejected: there is no
Layer 2 need once the field is built from the API, so nesting would import the
SDK into every middleware consumer for no benefit.

**Extend `httpx`.** Rejected: `httpx` is error responses and pagination — a
different concern with a different change cadence, and `AGENTS.md` explicitly
keeps `httpx` and `authmw` from importing each other so composition stays in the
service.

**Do nothing and weaken the contract** to say the skip list is per-service.
Rejected: the contract is the only thing that made F-2 findable.

## Consequences

**Gain:** one reviewable diff for the next edge-observability change; the
`observability.md:178` claim becomes true; a new service inherits correct
probe filtering, honest trace ids and correct log levels on day one; the
tracing→logging order stops being a per-repo convention.

**Accept:**

- **A cross-repo adoption phase** — one `httpmw` release plus eleven service PRs
  and eleven image pins. Sequenced one service at a time, each independently
  revertable.
- **A new fan-in point.** `httpmw` joins `proto` as a module whose exported
  signature change touches every service. `pkg/AGENTS.md`'s rule applies: adding
  or changing an exported symbol is a cross-repo contract change.
- **Version coupling with `logger/zapx`.** `AGENTS.md` already notes that
  `logger/zapx` and `obsx` "version together in practice" because every
  `middleware/logging.go` pairs them; `httpmw` inherits that pairing and makes it
  explicit.
- **Genuinely service-specific middleware behaviour must be expressed as
  options**, not forks. Any service that needs a divergence and cannot express
  it as an option is a signal the abstraction is wrong.

## Implementation obligations

1. `httpmw` ships with tests covering both branches of every decision the audit
   found wrong: probe vs real path, span vs no span, 4xx vs 5xx.
2. `depguard` must reject an `obsx` or `otel/sdk` import from `httpmw` — add the
   rule with the module, so the layering is enforced and not merely documented.
3. Add the module to `pkg/README.md`, the Repository layout and Dependency rules
   in `pkg/AGENTS.md`, and confirm `make modules` discovers it (the Makefile's
   `-maxdepth 4` scan drops a deeper module silently).
4. `observability.md:147` loses its "target, not current reality" sentence only
   when adoption reaches **Complete** — not when this ADR is accepted.
5. Each adopting service PR deletes its `middleware/` copy in the same commit
   that adds the dependency; no service carries both.

## Validation and compliance

- Per service, after adoption: zero access-log records for `/health` and
  `/ready`; every real-request record carries a native `TraceId`; no record
  carries a `trace_id` string without a matching span.
- Fleet-wide, measurable in the ClickHouse log store the same way the audit
  measured the defect:
  `countIf(LogAttributes['trace_id']!='' and TraceId='')` → **0**.
- Run the local-stack E2E audit once per adoption wave, not per service.
- The `observability.md` PR-compliance checklist gains one line: an HTTP service
  uses `pkg/httpmw` rather than a local copy.

## Revisit triggers

- A second service needs a middleware behaviour that cannot be an option — the
  abstraction is wrong and should be reconsidered before forcing it.
- `pkg` gains cross-module dependencies, changing the tag-ordering calculus that
  makes this a cheap Layer 1 addition today.
- The gin dependency changes shape (a router migration would make a
  gin-specific middleware module the wrong container).

## References

- [Telemetry audit 2026-08-07](../../../observability/audit-2026-08-07.md) — findings F-1 and F-2, with the measurements
- [`docs/api/observability.md`](../../../api/observability.md) — the normative contract, `:147` and `:178`
- [`docs/api/logs.md`](../../../api/logs.md) — access-log field schema
- [RFC-0014](../../rfc/RFC-0014/) — the instrumentation policy this serves
- `duynhlab/pkg` — `AGENTS.md` (multi-module architecture, dependency rules, layering), `README.md` (module table, release runbook), `obsx/logctx.go`, `authmw` as the sibling precedent

## History

| Date | Status | Note |
|------|--------|------|
| 2026-08-08 | Proposed | Written from the telemetry audit's F-1/F-2 findings. Direction only — the F-1/F-2 fix lands as eleven in-place patches first, so this decision is not on the critical path for stopping the log noise. |
