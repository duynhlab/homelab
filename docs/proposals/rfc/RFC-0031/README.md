# RFC-0031 Cross-signal telemetry standard and ClickHouse operations

| Status | Scope | Research | Created | Last updated |
|--------|-------|----------|---------|--------------|
| provisional | platform-wide | [./research.md](./research.md) — gate passed 2026-09-16 | 2026-09-16 | 2026-09-16 |

## Summary

Adopt one application telemetry contract across logs, metrics, traces and
continuous profiles. Logging moves to pkg/obslog with native EventName;
metrics retain the OTel Meter API and VictoriaMetrics with stricter instrument,
bucket, cardinality and replay rules; profiling retains the shared Pyroscope
SDK path with an explicit label, overhead, lifecycle and correlation contract.

The detailed target contract is in [telemetry-contract.md](./telemetry-contract.md).
The dependency-ordered implementation work is in
[delivery-plan.md](./delivery-plan.md); neither document changes the current
application contract until this RFC and its resulting ADRs are accepted.

## Motivation

The platform transports logs and traces into ClickHouse, metrics into
VictoriaMetrics and profiles into Pyroscope, but the signals do not yet share
one enforceable application contract.
Operators infer event identity from messages and must know which legacy HTTP or
gRPC attributes each dashboard expects. The research audit also found
privacy-policy violations and propagation coupled to export configuration.
Two business histograms use generic defaults instead of reviewed
operation-specific boundaries, API service versions are missing from
cross-signal identity, and profiling has no reviewed overhead budget or
explicit verification gate despite being enabled fleet-wide.

### Goals

- Make every named business or lifecycle event queryable through native OTel EventName.
- Give all Go services and workers one context-first logging API with one tested redaction boundary.
- Preserve W3C trace correlation whether telemetry export is enabled or not.
- Provide stable ClickHouse queries for events, access records and trace-to-log investigation.
- Keep application metrics bounded and meaningful in VictoriaMetrics, including Temporal replay semantics and explicit histogram boundaries.
- Make Pyroscope coverage, profile labels, overhead, failure behavior and trace correlation verifiable.
- Complete the migration as one release, leaving no legacy query contract.

### Non-Goals

- Change product APIs, business workflows, retention periods or ClickHouse topology.
- Turn every diagnostic line into a named event.
- Add unbounded request, identity or payload data to logs or metrics.
- Move metrics or profiles into ClickHouse.
- Replace VictoriaMetrics or Pyroscope.

## Proposal

pkg/obslog becomes the only application logging facade. Its diagnostic methods
emit structured slog records. Its context-first event method emits an OTel log
record whose native EventName is a lower-case dot-separated, stable identifier.
The message is short display text; values belong in typed attributes.

The package owns severity mapping, common resource attributes, native trace and
span correlation, recursive redaction, output formatting, sampling and test
helpers. It writes safe structured JSON to stdout and directly creates the OTel
record used for export. It does not use otelzap, because that bridge maps a Zap
message to record body and cannot populate native EventName.

The release removes the legacy application contract: Zap imports, otelzap,
custom event, and access fields named path, status, code, duration, client_ip,
user_agent and peer. Access records use pinned OTel HTTP and RPC semantic
conventions, with an explicit duration unit where needed. W3C traceparent and
baggage propagation are installed independently of exporters.

Metrics keep their current OTel-to-VictoriaMetrics path. RFC-0031 standardizes
instrument ownership, units, bounded attributes, explicit histogram boundaries,
temporality and Temporal replay semantics; it does not add a second metrics
pipeline. Profiles keep the direct pyroscope-go path and receive a closed label
allowlist, centrally owned runtime sampling, non-critical failure policy,
bounded shutdown and an honest manual trace-to-profile workflow.

### User Stories

- As an on-call engineer, I can find payment.authorization.failed by EventName,
  follow its trace, and see safe error metadata without parsing a message.
- As a service owner, I use the same API in an HTTP handler, gRPC method,
  Temporal activity and consumer, with correlation inherited from context.
- As a security reviewer, I can prove that secrets, client IPs and full
  User-Agent values cannot leave through either stdout or OTLP.
- As an on-call engineer, I can trust a VictoriaMetrics percentile because its
  histogram buckets match the operation and its labels are bounded.
- As a performance investigator, I can find CPU, heap, goroutine and
  synchronization profiles for the same service/version and time window as a
  slow trace.

### Alternatives

| Option | Benefit | Cost | Status |
|--------|---------|------|--------|
| pkg/obslog facade over slog plus direct OTel Logs API | Native events, one policy boundary, stable service API | Fleet migration; OTel Logs API remains pre-1.0 | Proposed |
| Custom Zap facade | Smaller initial code diff | Requires a second native-event path and retains Zap | Rejected |
| Raw OTel Logs API in every service | Full record control | Duplicates redaction, correlation and tests | Rejected |
| Preserve VictoriaMetrics and Pyroscope with stricter shared contracts | No backend migration; fixes measured contract gaps | Requires metric/profile tests and service-version convergence | Proposed |
| Replace metrics or profiles during this RFC | One large observability redesign | Expands blast radius without solving the audited application gaps | Rejected |

For the detailed source comparison and migration inventory, see
[research.md](./research.md).

## Other solutions considered

| Option | Shape | Why not chosen |
|--------|-------|----------------|
| Keep legacy fields and dual-write | Let dashboards consume old and new attributes | Hides incomplete migration and preserves two contracts indefinitely |
| Parse event identity from message text | Use log search or regular expressions | Loses typed aggregation and makes alert/query behavior message-dependent |
| Add a separate event database | Emit business events outside the telemetry pipeline | Creates another reliability, security and operational surface without solving access and trace correlation |

## Decision outcome

**Chosen option:** undecided — architecture review pending.

**Rationale:** The research recommendation is the pkg/obslog facade over slog
plus the direct OTel Logs API because it is the only option that provides native
EventName and a single redaction boundary. Formal selection belongs to
architecture review.

**Decided:** pending architecture review.

## Architecture & Diagrams

The target-state diagram answers where each application signal is created and
stored.

Legend: cyan is an application process, blue is the Collector, green is shared
data, purple is the platform UI, and the pale signal colors distinguish logs,
metrics, traces and profiles.

~~~mermaid
flowchart LR
    A["Service or worker"] --> L["pkg/obslog<br/>logs"]
    A --> M["OTel Meter API<br/>metrics"]
    A --> T["OTel Tracer API<br/>traces"]
    A --> P["pyroscope-go<br/>profiles"]
    L --> O["OTLP Collector"]
    M --> O
    T --> O
    O --> VL["VictoriaLogs<br/>7d logs"]
    O --> VM["VictoriaMetrics<br/>metrics"]
    O --> VT["VictoriaTraces<br/>7d traces"]
    O --> CH["ClickHouse<br/>90d logs + traces"]
    P --> PY["Pyroscope<br/>7d profiles"]
    VL --> G["Grafana"]
    VM --> G
    VT --> G
    CH --> G
    PY --> G
    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef collector fill:#a5d8ff,color:#111,stroke:#1971c2;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    classDef log fill:#d3f9d8,color:#111,stroke:#2f9e44;
    classDef trace fill:#c5f6fa,color:#111,stroke:#0c8599;
    classDef profile fill:#f3d9fa,color:#111,stroke:#9c36b5;
    class A service;
    class O collector;
    class G platform;
    class CH data;
    class L,VL log;
    class M,VM metric;
    class T,VT trace;
    class P,PY profile;
~~~

## Design Details

The service-facing API is context-first. Event(ctx, name, message, attrs...)
sets EventName; diagnostic methods create ordinary records. Event names are
lowercase dot namespaces with no identifiers, status codes or other dynamic
values. Existing OpenTelemetry semantic conventions take precedence over
domain-specific attributes.

The facade applies an allow/deny policy recursively before either sink. It
always removes credentials, authorization material, cookies, tokens, secrets,
private keys, client IPs, full User-Agent values, raw request bodies and raw
peer addresses. It records safe error.type; exceptional paths may add bounded,
redacted exception data.

Every process provides service name, version and deployment environment.
Kubernetes metadata is added at the collector or platform layer where possible.
The shared propagator is W3C Trace Context plus Baggage, configured independently
from tracer, logger and exporter enablement.

The Go Logs API is pre-1.0. Keeping its direct use inside obslog confines that
compatibility risk to one shared package. The migration cost is intentional:
the owner selected a clean cutover, so old and new attribute schemas do not
coexist in production.

The proposal preserves the existing docs/api invariants: SemConv v1.41.0 stays
pinned until a deliberate obsx release; automatic HTTP/gRPC RED instruments are
not duplicated; W3C propagation stays independent from exporters; workflow code
stays deterministic and replay-safe; and telemetry shutdown remains bounded
after readiness/work draining. [telemetry-contract.md](./telemetry-contract.md)
defines the precise target data, privacy, Temporal and verification rules.

## Security considerations

This RFC strengthens the existing data policy by making redaction executable and
testable. Logs must never include passwords, authorization headers, cookies,
access or refresh tokens, API keys, private keys, database credentials, client
secrets, client IPs, full User-Agent strings, request bodies or peer addresses.
Sensitive business attributes require an explicit documented classification
before emission.

## Observability & SLO impact

Existing backend retention and availability objectives remain unchanged.
Grafana and ClickHouse queries move to native EventName and semantic access
attributes. VictoriaMetrics gains explicit checks for instrument ownership,
histogram usefulness and series bounds. Pyroscope gains coverage, label,
overhead and correlation checks. The release adds health gates for all four
signals.

## Rollout & rollback

After acceptance and ADR approval, implementation lands in this order:

1. Build and contract-test obslog, resource versioning and independent W3C propagation.
2. Migrate all listed services, workers, consumers and mockpay using the remediation matrix in [research.md](./research.md).
3. Verify metric contracts in VictoriaMetrics and profile coverage in Pyroscope.
4. Replace ClickHouse dashboards, query examples and runbooks in the same release.
5. Run Compose and Kind end-to-end audits across all four signals.

The full dependency order, acceptance criteria, checkpoints and risks are in
[delivery-plan.md](./delivery-plan.md).

Rollback pins the shared package and all application releases back to their
prior versions and restores the matching dashboard configuration together.
There is no dual-write compatibility mode. A partial rollout is a failed
rollout and must not be promoted.

## Testing / verification

- Unit tests cover native event creation, severity mapping, recursive redaction,
  error metadata, sampling, shutdown and propagation when export is disabled.
- Integration tests send HTTP, gRPC and Temporal records through the pinned
  Collector to a disposable ClickHouse schema and assert EventName, resource
  data and trace/span identifiers.
- Dashboard query tests prove no remaining access to the removed legacy fields.
- Metric tests prove bounded attributes, explicit business histogram
  boundaries, temporality and Temporal replay semantics in VictoriaMetrics.
- Profiling tests prove service/version labels, expected profile types,
  non-critical failure behavior and the documented trace-to-profile pivot.
- The full Compose and Kind E2E audit proves browser checkout, a business
  rejection, a dependency failure and both trace-to-log and log-to-trace paths.

## Resulting decisions

| Decision | ADR | Status |
|----------|-----|--------|
| Logging facade and native event representation | ../../adr/ADR-070-otel-native-logging-facade/ | Planned |
| Canonical event, access and privacy data contract | ../../adr/ADR-071-telemetry-event-data-contract/ | Planned |
| Fleet cutover and ClickHouse query migration | ../../adr/ADR-072-telemetry-clean-cutover/ | Planned |
| Metric instrument, cardinality and replay contract | ../../adr/ADR-073-application-metrics-contract/ | Planned |
| Continuous profiling identity and overhead contract | ../../adr/ADR-074-continuous-profiling-contract/ | Planned |

## Implementation History

No implementation has started. This RFC is provisional and must complete
architecture review and resulting ADR review before code, manifests, dashboards
or docs/api are changed as target state.

## Related

- [./research.md](./research.md) — source research, audit evidence and remediation matrix
- [telemetry-contract.md](./telemetry-contract.md) — proposed target contract
- [delivery-plan.md](./delivery-plan.md) — implementation plan after acceptance
- [Telemetry standards audit](../../../observability/audits/2026-09-16-telemetry-standards.md) — current-state evidence
- [API logging contract](../../../api/logs.md) — current deployed contract
- [API observability contract](../../../api/observability.md) — current deployed contract
- [API metrics contract](../../../api/metrics.md) — current deployed contract
- [API profiling contract](../../../api/profiling.md) — current deployed contract

---
_Last updated: 2026-09-16_
