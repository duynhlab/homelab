# ADR-071: Fix One Canonical Event, Access and Privacy Data Contract

> **Decision summary:** We will define one attribute schema for the wide access
> record, for named business events and for the privacy boundary that applies to
> every signal — semantic-convention keys at the pinned version wherever one exists,
> registered domain keys otherwise, and a deny list enforced before any sink. We
> accept that some diagnostic convenience is lost in exchange for records that mean
> the same thing on every service and never carry a secret.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-09-17 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | The attribute schema of access records and named events, the severity model, and the privacy rules that bind logs, spans, metrics and profiles alike |
| **Affected components** | `pkg/httpmw`, `pkg/grpcx`, `pkg/logger/slogx`, `pkg/temporalx`; every service's access log and named events; ClickHouse saved queries and dashboards; `docs/api/logs.md`, `docs/api/api.md` |
| **Related RFC** | [RFC-0031](../../rfc/RFC-0031/) |
| **Related research** | [research.md](../../rfc/RFC-0031/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0031 delivery plan Tasks 0.2, 2.1, 2.2, 4.1 |
| **Adoption** | Partial |

## Context

Today the fleet's access log carries `method`, `path`, `status`, `duration`,
`client_ip` and `user_agent` on HTTP and `method`, `code`, `duration`, `peer` on
gRPC. Those keys predate the semantic conventions the shared package pins, they
carry a raw path and a client address, and no document states which keys a named
event may carry or which values must never be emitted. Redaction exists but is not a
contract: the deny list is whatever the adapter happens to strip.

The same gaps recur in the other signals — an identifier that is fine on a span is
a cardinality bomb on a metric, and a header that is safe in a log is unsafe in
baggage, which leaves the process on every outbound call. A privacy rule written
per signal drifts; one written once and applied to all four does not.

## Scope

### In scope

- Required and forbidden attributes for the HTTP and gRPC access record, database,
  messaging, error, domain-decision and Temporal-activity situations.
- Event-name grammar, body rule, severity mapping.
- The privacy deny list and where identifiers may and may not appear across logs,
  spans, metrics, profiles and baggage.

### Out of scope

- The facade that emits the records — ADR-070.
- Metric instrument choice and bucket boundaries — ADR-073.
- Span naming, kind and status — ADR-075.
- The registry that will eventually generate this schema — ADR-076.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Never emit a secret | Redaction is a contract, not adapter behaviour; the deny list must be one list |
| 2 | Same key, same meaning fleet-wide | A query written against one service must return the same thing on the next |
| 3 | Pinned upstream conventions | `http.*`, `rpc.*`, `db.*` come from semconv at the version `obsx` pins, not from house names |
| 4 | Bounded cardinality by construction | Identifiers are allowed only where they cannot become a label |
| 5 | One wide record per call | Investigation reads one record and one span, not a join across scattered lines |

## Decision

We will fix the access record as one wide, unnamed record per served call carrying
`http.request.method`, `http.route`, `http.response.status_code` (HTTP) or
`rpc.system.name=grpc`, `rpc.method`, `rpc.status_code` (gRPC), plus `error.type`
only on an error outcome, with the envelope fields the platform already emits
(`level`, `timestamp`, `caller`, `message`, `trace_id`). Raw URL path, query string,
`client.address`, `network.peer.address` and `user_agent.original` are forbidden.
Duration is owned by the span and metric; the record does not invent a second one.

Named events use lowercase dot-separated operation classes with at least three
parts where the domain supports it, a concise display body, and typed attributes
registered in the catalog. Domain keys (`order.id`, `payment.provider`) are allowed
where operationally justified; raw payment tokens, idempotency keys, addresses,
emails and arbitrary user input are not.

The privacy boundary is one deny list — authorization, cookie, set-cookie, password,
passwd, token, access_token, refresh_token, client_secret, api_key, private_key,
secret — plus bodies, client IPs, peer addresses, full User-Agent strings,
connection strings, payment secrets and PAN-shaped values, applied before every sink
of every signal. Workflow, run, order, reservation and session identifiers may be
span or log attributes when justified and are forbidden from metric labels,
resource attributes, event names, profile labels and baggage.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Convention first** | Where the pinned semantic conventions define an attribute, that key is used; a house key for the same meaning is a defect |
| **Route, never path** | `http.route` is the matched low-cardinality template; raw path appears in no record |
| **Error only on error** | `error.type` is set on an error outcome and absent otherwise; an expected business rejection carries a bounded outcome attribute instead |
| **Grammar** | Event names contain no identifier, status code, provider response, route parameter or free text; body is display only, attributes carry values |
| **Severity** | TRACE 1 · DEBUG 5 · INFO 9 · WARN 13 · ERROR 17 · FATAL 21; expected business outcomes are INFO or WARN by the owning contract, not ERROR by default |
| **Deny list** | The list above is stripped before stdout, OTLP, span attributes and span events; matching is case-insensitive after key normalisation and recursive |
| **Identifier placement** | Attributes on spans and logs when justified; never labels, resource attributes, event names, profile labels or baggage |
| **Schema is API** | Changing a key or a name is a documented change, not a message-text edit |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — One schema on pinned semconv keys plus a registered domain vocabulary and one deny list** | Same meaning everywhere; queries survive; privacy testable | Legacy keys and raw path/client fields disappear; consumers must be updated in the same release | Selected |
| **B — Keep the deployed legacy keys and add the semconv keys beside them** | No consumer breakage | Two names for one fact forever; a dual-write window the RFC's greenfield rule forbids | Rejected |
| **C — Per-service schemas documented in each contract** | Local freedom | Cross-service queries become per-service dialects; nothing enforces the deny list | Rejected |
| **D — Rely on Collector-side redaction only** | Central | stdout still leaks; a misconfigured pipeline leaks silently | Rejected |

### Why the selected option won

Only one schema with one deny list can be tested once and trusted everywhere, and
only pinned upstream keys let the platform reuse standard dashboards and the
registry in ADR-076 without translation.

### Why the closest alternative lost

Carrying both key sets is a migration mechanism by another name; RFC-0031 decided
for a greenfield cutover with none, and two names for one fact is the exact drift
the registry exists to prevent.

## Consequences

### Positive consequences

- Every access record and named event is queryable with one key set across the fleet.
- The deny list is a contract with tests, not an adapter detail.
- Cardinality is bounded by placement rules, not by after-the-fact review.

### Negative consequences and accepted trade-offs

- Every saved ClickHouse query, dashboard and runbook that names a legacy access key
  changes in the cutover release.
- Client IP and User-Agent leave the access record; an investigation that needs them
  reads the edge access log, which ADR-060/ADR-061 already route to ClickHouse.
- Expected business outcomes stop being ERROR by default; alert rules that keyed on
  level must be re-checked.

### Neutral consequences

- Envelope fields are unchanged.
- The `event` attribute keeps its deployed key.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Freeze the initial catalog and the sensitive-field classification | Platform / owner | RFC-0031 Task 0.2 | Owner sign-off against the RFC's normative contract |
| Emit the fixed access record from shared HTTP and gRPC middleware | `duynhlab/pkg` | RFC-0031 Task 2.1 | Contract tests assert one summary, semconv keys, no raw path or peer fields |
| Apply the deny list before every sink in the facade and span helpers | `duynhlab/pkg` | RFC-0031 Tasks 1.1, 1.5 | Redaction suite covers nested values, errors, span attributes and span events |
| Rewrite ClickHouse queries, dashboards and runbooks to the canonical keys | Observability | RFC-0031 Task 4.1 | No saved SQL references a removed key |
| Publish the as-built schema | Platform docs | RFC-0031 Task 4.3 | `docs/api/logs.md` matches deployment |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Access record shape | Golden test per transport: required keys present, forbidden keys absent, `error.type` only on error |
| Event grammar | A name with an identifier, status code or space fails the catalog test |
| Deny list | Property test over nested payloads proves no deny-listed key or PAN-shaped value reaches stdout, OTLP, span attributes or span events |
| Identifier placement | Metric attribute allowlist test and profile label test reject every forbidden identifier |
| Consumer sync | ClickHouse queries in `docs/` execute against the cutover schema in the compose gate |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- The pinned semantic conventions rename a key this contract requires.
- An investigation class demonstrably needs a field the deny list forbids, and a
  keyed, access-controlled representation is approved by a security decision.
- The registry in ADR-076 becomes the generated source of this schema, at which
  point the tables here become references to it.

A changed decision requires a new ADR that supersedes this one.

## References

- [RFC-0031](../../rfc/RFC-0031/) — § Record model, § Canonical attributes, § Event catalog and ownership, § Privacy, redaction and sampling, § Security considerations
- [RFC-0031 research](../../rfc/RFC-0031/research.md)
- [ADR-070 — Log through one shared slog facade](../ADR-070-logging-facade-and-event-catalog/)
- [ADR-060 — Envoy access-log transport](../ADR-060-envoy-access-log-transport/)
- [ADR-061 — Edge log routing](../ADR-061-edge-log-routing/)
- [Logging contract (as-built)](../../../api/logs.md)
- [Shared API conventions](../../../api/api.md)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-09-17 | Proposed / Not started | Drafted during RFC-0031 architecture review from § Record model, § Canonical attributes and § Privacy |
| 2026-09-17 | Accepted / Not started | Owner accepted with the RFC; created at `Accepted` per the RFC-0028/RFC-0030 precedent |
| 2026-09-23 | Accepted / Partial | The deny list is code: `logger/slogx` v0.1.0 applies it before every sink, on the message and on attributes bound with `With`, recursing through groups, maps, slices, structs, errors and `LogValuer`s, and scans values for credential shapes (Bearer/Basic, JWT, a `key=value` pair whose key is denied, URL userinfo, Luhn-valid card numbers) as well as keys. The policy can only be tightened by a service. Two security audits drove the implementation; their probes are the regression table. The envelope keys are reserved so a caller attribute cannot make the two sinks disagree about one record |
| 2026-09-23 | Accepted / Partial | **Task 0.2 frozen.** The initial catalog is nineteen names across the five classes, admitted only when an operator would query them by name across services; the access record keeps its fixed schema and gains a written severity mapping; every field is classified allow, correlation-only, review or deny; each schema has one owner. All of it lives in `docs/api/logs.md` § Event catalog. The gRPC status key is corrected to `rpc.response.status_code`, the key the pinned instrumentation writes |

---
_Last updated: 2026-09-23 — Task 0.2 frozen: catalog, access severity, field classification and schema owners in logs.md. Previously 2026-09-23 — the privacy boundary ships in `logger/slogx` v0.1.0, keys and values, before both sinks. Previously 2026-09-17._
